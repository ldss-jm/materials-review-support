require 'json'
load './class_sersol.rb'
load './class_nonsersol.rb'
load './metadata_api.rb'


# check after running
#  dump every used sersol entry end_date descriptor to look for nonconforming date or embargo statement
#  dump ssjs not in sersol report
#  dump extra matches
#TODO: missing/wmissing arrays should not exist

# questions
#    for the resource column, access point ties are being concatenated into "access1 | access2 etc."
#    providing "x units ago" for all embargo dates -- okay?
#    interpret jstor embargo. i'm using only year -- okay?
#       if jstor has a end_date of 3/01/16 or 10/30/16, both end up being "1 year ago"
#    is it the case that current>embargo>fixed, regardless of embargo length?


#
# it's better to exclude |y on the export. it leads to false positives and got better results looking up oclc nums in worldcat
# to match up w/ sersol report
#

# problematic embargo preference
#ssj0000529	Journal	ARTnews	0004-3273	2327-1221	2/17/1923	9/13/1924	JSTOR Arts & Sciences VIII	http://libproxy.lib.unc.edu/login?url=http://www.jstor.org/journal/artnews1923	yes
#ssj0000529	Journal	ARTnews	0004-3273	2327-1221	1/1/1997	5/2/2000	Factiva	http://libproxy.lib.unc.edu/login?url=http://global.factiva.com/en/sess/login.asp?xsid=S003Wvl2cN72dmnNdmnMTMoMDAnMTIm5DByMU38ODJ9RcyqUUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUEA	Yes

#no alt
#ssj0006315	Journal	Slavonic and East European review. American series	1535-0940	2330-6246	3/1/1943	12/31/1944	JSTOR Arts & Sciences II	http://libproxy.lib.unc.edu/login?url=http://www.jstor.org/journal/slaveasteurorevi	yes


secretfile = 'metadata.secret'
api = MetadataAPI.new
api.get_keys(secretfile)


# ifiles
# replace any newlines, make tab-delim
#check wiley for newlines
mil_export_file = 'split_issn_jcm.txt'
sersol_file = 'sersol.txt'
wiley_file = 'wiley.txt'

# output files
extramatch = 'output_problem_extramatches.txt'
output_current = 'output_current.txt'
output_noncurrent = 'output_noncurrent.txt'
output_wiley_current = 'output_wiley_current.txt'
output_wiley_noncurrent = 'output_wiley_noncurrent.txt'
output_wiley_extras = 'output_problem_wiley_extramatches.txt'
scraped_issn_file = 'scraped_issns.json'

output_headers = ['matchcount', 'bib_identifier_notes', 'all_issns',
                  'matching_ssj', 'matching_title', 'best_end_type', 'best_end_date',
                  'best_end_resources']

$ssjs_not_in_sersol_report = []


# removes the first SersolTitle from a record
#
def delete_extra(arry, indx)
  arry[indx].ss_match = Set.new(arry[indx].ss_match.to_a.drop(1))
end




#
# IMPORT SERSOL RECORDS
#
lines = []
File.open(sersol_file, 'rb:bom|utf-16:utf-8') do |f|
  lines = f.read.split("\n")
end
ss_headers = lines.delete_at(0).rstrip.downcase.split("\t")

sersol_records = []
blacklist = []
lines.each do |line|
  sersol = SersolEntry.new(Hash[ss_headers.zip(line.rstrip.split("\t"))])
  if not sersol.blacklisted
    sersol_records << sersol
  else
    blacklist << sersol.ssj
  end
end

sersol_by_ssj = {}
sersol_records.each do |entry|
  if entry.blacklisted == false
    ssj = entry.ssj
    if not sersol_by_ssj.include?(ssj)
      sersol_by_ssj[ssj] = SersolTitle.new(ssj)
    end
    sersol_by_ssj[ssj].entries << entry
  end
end

issn_to_sersol = {}
omg_issns_mapping_to_different_ssjs = []
sersol_by_ssj.each do |ssj, ss_match|
  ss_match.all_issns.each do |issn|
    if issn_to_sersol.include?(issn)
      if issn_to_sersol[issn] != ss_match
        omg_issns_mapping_to_different_ssjs << issn
        issn_to_sersol[issn] << ss_match
      end
    else
      issn_to_sersol[issn] = [ss_match]
    end
  end
end
#
# End sersol
#



#
# IMPORT MIL RECORDS
#
lines = []
File.open(mil_export_file, 'rb:bom|utf-16:utf-8') do |f|
  lines = f.read.split("\n")
end
mil_headers = lines.delete_at(0).rstrip.downcase.split("\t")

mil_records = []
lines.each do |line|
  mil_records << MilEntry.new(Hash[mil_headers.zip(line.rstrip.split("\t"))])
end

mil_records.each do |mrec|
  mrec.all_issns
  mrec.get_matches(sersol_by_ssj, issn_to_sersol, blacklist)
end

no_matches = []
mil_records.each do |mrec|
  if mrec.match_count == 0
    no_matches << mrec
  end
end

# check no_matches 001 against worldcat


hsh = {}
File.open(scraped_issn_file, 'r') do |f|
  hsh = JSON.parse(f.read)
end

i=0
no_matches.each do |mrec|
  puts "checking record #{i.to_s} of #{no_matches.length}"
  #get scraped issns from hsh, else scrape_issns
  if hsh.include?(mrec._001)
    mrec.scraped_issns = hsh[mrec._001]
    puts "used scraped issns on file"
  else
    mrec.scrape_issns(api)
    puts "checking worldcat"
  end
  mrec.gen_all_issns
  mrec.get_matches(sersol_by_ssj, issn_to_sersol, blacklist)
  if mrec.match_count < 1
    mrec.add_022y
    mrec.get_matches(sersol_by_ssj, issn_to_sersol, blacklist)
    if mrec.match_count >= 1
      mrec.note += 'matched using 022|y; '
    end
  else
    mrec.note += 'matched using issns from worldcat lookup; '
  end
  i += 1
end
hsh_out = {}
mil_records.each do |mrec|
  if mrec.scraped_issns and not mrec.scraped_issns.empty?
    hsh_out[mrec._001] = mrec.scraped_issns.to_a
  end
end
File.open(scraped_issn_file, 'w') do |f|
  f.write(hsh_out.to_json)
end



=begin
new_matches = []
no_matches.each do |mrec|
  if mrec.match_count > 0
    new_matches << mrec
  end
end
=end


matched = []
extra_matches = []
missing = []
mil_records.each do |mrec|
  if mrec.match_count <= 1
    matched << mrec
  elsif mrec.match_count > 1
    extra_matches << mrec
  end
  if not (matched + extra_matches).include?(mrec)
    missing << mrec
  end  
end

mil_output_headers = mil_headers + output_headers

File.write(output_noncurrent, mil_output_headers.join("\t")+"\n")
File.write(output_current, mil_output_headers.join("\t")+"\n")

File.open(output_noncurrent, 'a') do |noncurrent|
  File.open(output_current, 'a') do |current|
    matched.each do |record|
      if record.match_count == 1
        _end = record.ss_match.first.most_recent_end()
        if _end['date'] == 'current'
          current.write(record.print_output(mil_headers) + "\n")
        else
          noncurrent.write(record.print_output(mil_headers) + "\n")
        end
      else  #no_matches
        noncurrent.write(record.print_output(mil_headers) + "\n")
      end
    end
  end
end

i = 0
File.open(extramatch, 'w') do |f|
  extra_matches.each do |record|
    f.write(i.to_s + "\n")
    f.write(record.print_extras(mil_headers)+"\n")
    i += 1
  end
end

sorted_extras = []
extra_matches.each do |record|
  s = record.ss_match
  s_sorted = s.to_a.sort_by { |s| [s.most_recent_end['mode'][-1], s.most_recent_end['comparator']]}.reverse
  record.ss_match = s_sorted
  sorted_extras << record
end
extra_matches = nil


#
# IMPORT WILEY RECORDS
#
lines = []
File.open(wiley_file, 'rb:bom|utf-16:utf-8') do |f|
  lines = f.read.split("\n")
end
wiley_headers  = lines.delete_at(0).rstrip.downcase.split("\t")

wiley_records = []
lines.each do |line|
  wiley_records << WileyEntry.new(Hash[wiley_headers.zip(line.rstrip.split("\t"))])
end

wiley_records.each do |mrec|
  mrec.all_issns
  mrec.get_matches(sersol_by_ssj, issn_to_sersol, blacklist)
end

wmatched = []
wextra_matches = []
wmissing = []
wiley_records.each do |wrec|
  if wrec.match_count <= 1
    wmatched << wrec
  elsif wrec.match_count > 1
    wextra_matches << wrec
  end
  if not (wmatched + wextra_matches).include?(wrec)
    wmissing << mrec
  end  
end

wiley_output_headers = wiley_headers + output_headers
File.write(output_wiley_noncurrent, wiley_output_headers.join("\t")+"\n")
File.write(output_wiley_current, wiley_output_headers.join("\t")+"\n")

File.open(output_wiley_noncurrent, 'a') do |noncurrent|
  File.open(output_wiley_current, 'a') do |current|
    wmatched.each do |record|
      if record.match_count == 1
        _end = record.ss_match.first.most_recent_end()
        if _end['date'] == 'current'
          current.write(record.print_output(wiley_headers) + "\n")
        else
          noncurrent.write(record.print_output(wiley_headers) + "\n")
        end
      else  #no_matches
        noncurrent.write(record.print_output(wiley_headers) + "\n")
      end
    end
  end
end

i = 0
File.open(output_wiley_extras, 'w') do |f|
  wextra_matches.each do |record|
    f.write(i.to_s + "\n")
    f.write(record.print_extras(wiley_headers)+"\n")
    i += 1
  end
end

wiley_sorted_extras = []
wextra_matches.each do |record|
  s = record.ss_match
  s_sorted = s.to_a.sort_by { |s| [s.most_recent_end['mode'][-1], s.most_recent_end['comparator']]}.reverse
  record.ss_match = s_sorted
  wiley_sorted_extras << record
end
wextra_matches = nil


# RUN CHECKS
#
#
#gets enddate_descriptors for used sersol entries
all_end_date_descriptors = []
mil_records.each do |rec|
  if rec.all_entries
    rec.all_entries.each do |entry|
      all_end_date_descriptors << entry.enddate_descriptor
    end
  end
end
wiley_records.each do |rec|
  if rec.all_entries
    rec.all_entries.each do |entry|
      all_end_date_descriptors << entry.enddate_descriptor
    end
  end
end


File.write('CHECK_used_date_descriptors.txt',
           Set.new(all_end_date_descriptors).to_a.join("\n"))

=begin
screened_for_blacklist = []
blacklist_ssjs = []
blacklist.each do |entry|
  blacklist_ssjs << entry.ssj
end
$ssjs_not_in_sersol_report.each do |ssj|
  if not blacklist_ssjs.include?(ssj)
    screened_for_blacklist << ssj
  end
end

File.write('CHECK_ssjs_not_in_sersol_report.txt',
           Set.new(screened_for_blacklist).to_a.join("\n"))
=end

File.write('CHECK_ssjs_not_in_sersol_report.txt',
           Set.new($ssjs_not_in_sersol_report).to_a.join("\n"))

#check for sersol entries without blacklist
if blacklist.empty?
  File.write('CHECK_it_looks_like_blacklist_not_enabled.txt',
           'is it?')
end

missing.length
wmissing.length
#TODO: missing/wmissing arrays should not exist

# CORRECT MIL and WILEY EXTRAS
#
#  make any needed corrections to sorted_extras
#  by using: delete_extra(sorted_extras, i)
#  and:      delete_extra(wiley_sorted_extras, i)
# for any record where the first record was incorrect
#
#
# then, when extras correct
#

File.open(output_noncurrent, 'a') do |noncurrent|
  File.open(output_current, 'a') do |current|
    sorted_extras.each do |record|
      _end = record.ss_match.first.most_recent_end()
      if _end['date'] == 'current'
        current.write(record.print_output(mil_headers) + "\n")
      else
        noncurrent.write(record.print_output(mil_headers) + "\n")
      end
    end
  end
end

File.open(output_wiley_noncurrent, 'a') do |noncurrent|
  File.open(output_wiley_current, 'a') do |current|
    wiley_sorted_extras.each do |record|
      _end = record.ss_match.first.most_recent_end()
      if _end['date'] == 'current'
        current.write(record.print_output(wiley_headers) + "\n")
      else
        noncurrent.write(record.print_output(wiley_headers) + "\n")
      end
    end
  end
end
