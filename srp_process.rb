require 'csv'
require 'json'
require_relative 'sersol'
require_relative 'nonsersol'
load '../worldcat_api_and_wcm/metadata_api.rb'


=begin
Input: (tab-delim, utf-16, no newlines in data)
  set of sersol records
  set(s) of non-sersol records (e.g. Sierra records, publisher title list records)

Matches non-sersol records to sersol records by ssj or good issns
For Sierra records, if no matches:
  scrapes worldcat api for issns to match
  if still no matches, tries to match using Sierra 022|y
Writes recs with best current resource to current output file
Writes recs with best noncurrent resource (incl nothing when no matches) to
  noncurrent output file,
If a non-sersol records matches multiple sersol records, exclude those from
  the above, write to separate file, examine, identify appropriate match,
  manually remove inappropriate match if needed and write to file

Produces a couple of output files to check
  all end_date descriptors to identify nonconforming date/embargo values
  any ssjs in non-sersol records not found in sersol report
  the extra match file

#
# NOTES
#
approved by er for srp17:
  current > embargo > fixed, regardless of embargo length
    e.g. this JSTOR embargo is still better than the fixed-end access point
      ARTnews 2/17/1923	9/13/1924	JSTOR Arts & Sciences VIII
      ARTnews 1/1/1997	5/2/2000	Factiva
  for the resource column, access point ties are being concatenated into:
    "access1 | access2 etc."
  providing "x units ago" for all embargo dates
  jstor embargo interpretation uses only year
    e.g. if jstor has a end_date of 3/01/16 or 10/30/16, both end up being:
      "1 year ago"
ldss notes:
it's better to exclude |y on the export except as last resort, and 022|y matches
should be reviewed. 022|y leads to false positives and we got better results
looking up oclc nums in worldcat to match up w/ sersol report


=end

#no alt
#ssj0006315	Journal	Slavonic and East European review. American series	1535-0940	2330-6246	3/1/1943	12/31/1944	JSTOR Arts & Sciences II	http://libproxy.lib.unc.edu/login?url=http://www.jstor.org/journal/slaveasteurorevi	yes


secretfile = File.dirname(__FILE__).to_s + '/../worldcat_api_and_wcm/kms.metadata.secret'
api = MetadataAPI.new(secretfile)


process_sierra = false
process_titlelist = true

# input files  **tab-delim, utf16, no newlines in data
MIL_EXPORT_FILE = 'sierra.txt'
SERSOL_FILE = 'sersol.txt'
TITLELIST_FILE = 'titlelist.txt'

# output files
OUTPUT_SIERRA = 'output_sierra.txt'
OUTPUT_TITLELIST = 'output_titlelist.txt'
OUTPUT_SIERRA_EXTRAS = 'output_problem_sierra_extramatches.txt'
OUTPUT_TITLELIST_EXTRAS = 'output_problem_titlelist_extramatches.txt'
SCRAPED_ISSN_FILE = 'scraped_issns.json'

OUTPUT_HEADERS = ['matchcount', 'bib_identifier_notes', 'all_issns',
                  'matching_ssj', 'matching_title',
                  'best_end_type',
                  'best_end_date',
                  'best_end_resources',
                  #'bestfree_end_type',
                  #'bestfree_end_date',
                  #'bestfree_end_resources'
                ]

$ssjs_not_in_sersol_report = []


# removes the first SersolTitle from a record
#
def delete_extra(arry, indx)
  arry[indx].ss_match = Set.new(arry[indx].ss_match.to_a.drop(1))
end

# prints records in reclist to outfile
def export_results(opt)
  reclist = opt[:reclist]
  ofile = opt[:ofile]
  output_headers = opt[:output_headers]
  custom_headers = opt[:custom_headers]
  mode = 'w' unless opt[:mode] == 'a'
  headers = custom_headers + output_headers
  File.open(ofile, mode) do |outfile|
    outfile << headers.join("\t")+"\n" if mode == 'w'
    i=0
    reclist.each do |record|
      puts i+=1
      output = "#{record.print_output(custom_headers)}\n"
      # _end = record.ss_match.first.most_recent.first
      #s = record.ss_match.first&.most_recent_data()
      begin
        outfile << output
      rescue
        return record
      end
    end
  end
end


#
# IMPORT SERSOL RECORDS
#
sersol_records = []
blacklist = []
#File.open(SERSOL_FILE, 'rb:bom|utf-16:utf-8') do |f|
#  lines = f.read.split("\n")
#  ss_headers = lines.delete_at(0).rstrip.downcase.split("\t")
#  lines.each do |r|
#    sersol = SersolEntry.new(Hash[ss_headers.zip(r.rstrip.split("\t"))])
#    if sersol.blacklisted?
#      blacklist << sersol.ssj
#    else
#      sersol_records << sersol
#    end
#  end
#end

sersol_csv = CSV.open(SERSOL_FILE, 'rb:utf-8',
                      headers: true,
                      header_converters: :downcase,
                      col_sep: "\t",
                      quote_char: "\x00")
sersol_csv.each do |r|
  sersol = SersolEntry.new(r.to_h)
  if sersol.blacklisted?
    blacklist << sersol.ssj
    next
  end
  sersol_records << sersol
end
ss_headers = sersol_csv.headers
sersol_csv.close

# hash of sersoltitles by ssj#
sersol_by_ssj = {}
sersol_records.each do |entry|
  unless entry.blacklisted?
    ssj = entry.ssj
    sersol_by_ssj[ssj] = SersolTitle.new(ssj) unless sersol_by_ssj.include?(ssj)
    sersol_by_ssj[ssj].entries << entry
  end
end
sersol_records = nil

# hash of sersoltitles by issn
issn_to_sersol = {}
sersol_by_ssj.values.each do |sstitle|
  sstitle.all_issns.each do |issn|
    if issn_to_sersol.include?(issn)
      issn_to_sersol[issn] << sstitle
    else
      issn_to_sersol[issn] = [sstitle]
    end
  end
end

# there's not really anything to do with this omg list
# any title list records who have issns (or issn/ssj combo)
# that map them to multiple sersol titles get fixed
# w/ the extra matches fixing
omg_issns_mapping_to_different_ssjs =
  issn_to_sersol.select{ |k,v| v.length > 1 }.keys

#
# End sersol
#


#
# IMPORT MIL RECORDS
#
mil_records = []
if process_sierra
  mil_headers = ''
  File.open(MIL_EXPORT_FILE, 'rb:bom|utf-16:utf-8') do |f|
    lines = f.read.split("\n")
    mil_headers = lines.delete_at(0).rstrip.downcase.split("\t")
    lines.each do |r|
      m = MilEntry.new(Hash[mil_headers.zip(r.rstrip.split("\t"))])
      m.get_matches(sersol_by_ssj, issn_to_sersol, blacklist)
      mil_records << m
    end
  end

  #
  # use fallback methods to find matches for unmatched records
  #
  no_matches = mil_records.select { |r| r.match_count == 0 }
  prev_scraped = ''
  File.open(SCRAPED_ISSN_FILE, 'r') { |f| prev_scraped = JSON.parse(f.read) }

  i=0
  no_matches.each do |mrec|
    puts "checking record #{i.to_s} of #{no_matches.length}"
    # use previously scraped issns if found
    if prev_scraped.include?(mrec._001)
      puts "used scraped issns on file"
      mrec.scraped_issns = prev_scraped[mrec._001]
    # otherwise scrape issns
    else
      puts "checking worldcat"
      mrec.scrape_issns(api)
      prev_scraped[mrec._001] = mrec.scraped_issns.to_a
    end
    mrec.add_scraped_issns
    mrec.get_matches(sersol_by_ssj, issn_to_sersol, blacklist)
    if mrec.match_count >= 1
      mrec.note += 'matched using issns from worldcat lookup; '
    # try matching on 022y if still no matches
    else
      mrec.add_022y
      mrec.get_matches(sersol_by_ssj, issn_to_sersol, blacklist)
      mrec.note += 'matched using 022|y; ' if mrec.match_count >= 1
    end
    i += 1
  end
  # write scraped issns to file
  File.open(SCRAPED_ISSN_FILE, 'w') do |f|
    f.write(prev_scraped.to_json)
  end

  matched = mil_records.select{ |r| r.match_count <= 1}
  extra_matches = mil_records.select{ |r| r.match_count > 1}
  missing = mil_records - (matched + extra_matches)

  export_results(reclist: matched, ofile: OUTPUT_SIERRA,
                output_headers: OUTPUT_HEADERS,
                custom_headers: mil_headers, mode: 'w')

  i = 0
  File.open(OUTPUT_SIERRA_EXTRAS, 'w') do |f|
    extra_matches.each do |record|
      f.write(i.to_s + "\n")
      f.write(record.print_extras(mil_headers)+"\n")
      i += 1
    end
  end

  sorted_extras = []
  extra_matches.each do |record|
    s = record.ss_match
    s_sorted = s.to_a.sort_by { |s| [s.most_recent_data[:modevalue], s.most_recent_data[:comparator]]}.reverse
    record.ss_match = s_sorted
    sorted_extras << record
  end
  extra_matches = nil
end

#
# IMPORT TITLELIST RECORDS
#
titlelist_records = []
if process_titlelist
  titlelist_headers = ''
  File.open(TITLELIST_FILE, 'rb:bom|utf-16:utf-8') do |f|
    lines = f.read.split("\n")
    titlelist_headers  = lines.delete_at(0).rstrip.downcase.split("\t")
    lines.each do |r|
      w = TitlelistEntry.new(Hash[titlelist_headers.zip(r.rstrip.split("\t"))])
      w.get_matches(sersol_by_ssj, issn_to_sersol, blacklist)
      titlelist_records << w
    end
  end

  #sersol_csv = CSV.open(SERSOL_FILE, 'rb:utf-8',
  #                      headers: true,
  #                      header_converters: :downcase,
  #                      col_sep: "\t",
  #                      quote_char: "\x00")
  #  sersol_csv.each do |r|
  #    sersol = SersolEntry.new(r.to_h)
  #    if sersol.blacklisted?
  #      blacklist << sersol.ssj
  #      next
  #    end
  #    sersol_records << sersol
  #  end
  #  ss_headers = sersol_csv.headers
  #  sersol_csv.close

  wmatched = titlelist_records.select { |r| r.match_count <= 1 }
  wextra_matches = titlelist_records.select { |r| r.match_count > 1 }

  export_results(reclist: wmatched, ofile: OUTPUT_TITLELIST,
    output_headers: OUTPUT_HEADERS,
    custom_headers: titlelist_headers, mode: 'w')

  i = 0
  File.open(OUTPUT_TITLELIST_EXTRAS, 'w') do |f|
    wextra_matches.each do |record|
      f.write(i.to_s + "\n")
      f.write(record.print_extras(titlelist_headers)+"\n")
      i += 1
    end
  end

  titlelist_sorted_extras = []
  wextra_matches.each do |record|
    s = record.ss_match
    s_sorted = s.to_a.sort_by { |s| [s.most_recent_data[:modevalue], s.most_recent_data[:comparator]]}.reverse
    record.ss_match = s_sorted
    titlelist_sorted_extras << record
  end
  wextra_matches = nil
end


# RUN CHECKS
#
#
#gets enddate_descriptors for used sersol entries
all_end_date_descriptors = []
(mil_records.to_a + titlelist_records.to_a).each do |rec|
  next unless rec.all_entries
  rec.all_entries.each do |entry|
    all_end_date_descriptors << entry.enddate_descriptor
  end
end
File.write('CHECK_used_date_descriptors.txt',
           Set.new(all_end_date_descriptors).to_a.join("\n"))

File.write('CHECK_ssjs_not_in_sersol_report.txt',
           Set.new($ssjs_not_in_sersol_report).to_a.join("\n"))

# CORRECT MIL and TITLELIST EXTRAS
#
#  make any needed corrections to sorted_extras
#  by using: delete_extra(sorted_extras, i)
#  and:      delete_extra(titlelist_sorted_extras, i)
# for any record where the first record was incorrect
#
#
# then, when extras correct
#

raise(RuntimeError, "stop here if running as script")

export_results(reclist: sorted_extras, ofile: OUTPUT_SIERRA,
  output_headers: OUTPUT_HEADERS,
  custom_headers: mil_headers, mode: 'a')

export_results(reclist: titlelist_sorted_extras, ofile: OUTPUT_TITLELIST,
  output_headers: OUTPUT_HEADERS,
  custom_headers: titlelist_headers, mode: 'a')

