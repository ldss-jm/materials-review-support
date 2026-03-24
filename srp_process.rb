require 'csv'
require 'json'
require_relative 'sersol'
require_relative 'nonsersol'

# Input:
#   - set of sersol records (utf16 csv)
#     - sersol provided in 2026 as utf16 csv (previously was tsv). If received
#       in multiple parts, cat into one file (removing repeated header lines)
#   - set of sierra records (utf8 tsv)
#     - disallow newlines in data
#   - (optional) set of titlelist records (utf16 tsv)
#
# Matches non-sersol records to sersol records by ssj or good issns
# For Sierra records, if no matches:
#   if still no matches, tries to match using Sierra 022|y
# Writes recs with best current resource to current output file
# Writes recs with best noncurrent resource (incl nothing when no matches) to
#   noncurrent output file,
# If a non-sersol records matches multiple sersol records, exclude those from
#   the above, write to separate file, examine, identify appropriate match,
#   manually remove inappropriate match if needed and write to file
#
# Produces a couple of output files to check
#   all end_date descriptors to identify nonconforming date/embargo values
#   any ssjs in non-sersol records not found in sersol report
#   the extra match file

#
# NOTES
#
# approved by er for srp17:
#   current > embargo > fixed, regardless of embargo length
#     e.g. this JSTOR embargo is still better than the fixed-end access point
#       ARTnews 2/17/1923	9/13/1924	JSTOR Arts & Sciences VIII
#       ARTnews 1/1/1997	5/2/2000	Factiva
#   for the resource column, access point ties are being concatenated into:
#     "access1 | access2 etc."
#   providing "x units ago" for all embargo dates
#   jstor embargo interpretation uses only year
#     e.g. if jstor has a end_date of 3/01/16 or 10/30/16, both end up being:
#       "1 year ago"
# ldss notes:
# it's better to exclude |y on the export except as last resort, and 022|y
# matches should be reviewed. 022|y leads to false positives and we got better
# results looking up oclc nums in worldcat to match up w/ sersol report


process_sierra = true
process_titlelist = false

# input files:
MIL_EXPORT_FILE = 'sierra.utf8.txt'.freeze
SERSOL_FILE = 'sersol.csv'.freeze
TITLELIST_FILE = 'titlelist.txt'.freeze

# output files
OUTPUT_SIERRA = 'output_sierra.txt'.freeze
OUTPUT_TITLELIST = 'output_titlelist.txt'.freeze
OUTPUT_SIERRA_EXTRAS = 'output_problem_sierra_extramatches.txt'.freeze
OUTPUT_TITLELIST_EXTRAS = 'output_problem_titlelist_extramatches.txt'.freeze
SCRAPED_ISSN_FILE = 'scraped_issns.json'.freeze

OUTPUT_HEADERS = %w[matchcount bib_identifier_notes all_issns matching_ssj
                    matching_title
                    best_paid_type best_paid_date best_paid_resources
                    best_free_type best_free_date best_free_resources].freeze

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
  File.open(ofile, "#{mode}:utf-8", ) do |outfile|
    outfile << headers.join("\t") + "\n" if mode == 'w'
    i = 0
    reclist.each do |record|
      puts i += 1
      output = "#{record.print_output(custom_headers)}\n"
      # _end = record.ss_match.first.most_recent.first
      # s = record.ss_match.first&.most_recent_data()
      begin
        outfile << output
      rescue => e
        puts record
        raise e
      end
    end
  end
end

#
# IMPORT SERSOL RECORDS
#
sersol_records = []
exclude_list = []

sersol_csv = CSV.open(SERSOL_FILE,
                      'rb:bom|utf-16:utf-8',
                      headers: true,
                      header_converters: :downcase)
sersol_csv.each do |r|
  sersol = SersolEntry.new(r.to_h)
  if sersol.excluded?
    exclude_list << sersol.ssj
    next
  end
  sersol_records << sersol
end
puts "sersol headers: #{sersol_csv.headers}"
sersol_csv.close

# hash of sersoltitles by ssj#
sersol_by_ssj = {}
sersol_records.each do |entry|
  next if entry.excluded?
  ssj = entry.ssj
  sersol_by_ssj[ssj] = SersolTitle.new(ssj) unless sersol_by_ssj.include?(ssj)
  sersol_by_ssj[ssj].entries << entry
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
#
# End sersol
#

#
# IMPORT MIL RECORDS
#
mil_records = []
if process_sierra
  mil_headers = ''
  mil_csv = CSV.open(MIL_EXPORT_FILE,
                           'r:utf-8',
                           headers: true,
                           header_converters: :downcase,
                           col_sep: "\t",
                           quote_char: "\x00")
  mil_csv.each do |r|
    m = MilEntry.new(r.to_h)
    m.get_matches(sersol_by_ssj, issn_to_sersol, exclude_list)
    mil_records << m
  end
  mil_headers = mil_csv.headers
  mil_csv.close

  #
  # use fallback methods to find matches for unmatched records
  #
  no_matches = mil_records.select { |r| r.match_count.zero? }

  prev_scraped =
    begin
      File.open(SCRAPED_ISSN_FILE, 'r') { |f| prev_scraped = JSON.parse(f.read) }
    rescue Errno::ENOENT # prev_scraped file does not exist
      {}
    end

  i = 0
  no_matches.each do |mrec|
    puts "checking record #{i} of #{no_matches.length}"
    puts mrec._001
    mrec.add_022y
    mrec.get_matches(sersol_by_ssj, issn_to_sersol, exclude_list)
    mrec.note += 'matched using 022|y; ' if mrec.match_count >= 1

    i += 1
  end

  matched = mil_records.select { |r| r.match_count <= 1 }
  extra_matches = mil_records.select { |r| r.match_count > 1 }
  extra_matches.each do |record|
    record.note += "check manually due to multiple matching sersol titles"
  end

  export_results(reclist: matched + extra_matches, ofile: OUTPUT_SIERRA,
                 output_headers: OUTPUT_HEADERS,
                 custom_headers: mil_headers, mode: 'w')

  i = 0
  File.open(OUTPUT_SIERRA_EXTRAS, 'w') do |f|
    extra_matches.each do |record|
      f.write(i.to_s + "\n")
      f.write(record.print_extras(mil_headers) + "\n")
      i += 1
    end
  end

  sorted_extras = []
  extra_matches.each do |record|
    s = record.ss_match
    s_sorted = s.to_a.sort_by { |s|
      [s.most_recent_data[:modevalue], s.most_recent_data[:comparator]]
    }.reverse
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
  titlelist_csv = CSV.open(TITLELIST_FILE,
                           'rb:bom|utf-16:utf-8',
                           # 'rb:utf-8',
                           headers: true,
                           header_converters: :downcase,
                           col_sep: "\t",
                           quote_char: "\x00")
  titlelist_csv.each do |r|
    title = TitlelistEntry.new(r.to_h)
    title.get_matches(sersol_by_ssj, issn_to_sersol, exclude_list)
    titlelist_records << title
  end
  titlelist_headers = titlelist_csv.headers
  titlelist_csv.close

  wmatched = titlelist_records.select { |r| r.match_count <= 1 }
  wextra_matches = titlelist_records.select { |r| r.match_count > 1 }
  wextra_matches.each do |record|
    record.note += "check manually due to multiple matching sersol titles"
  end

  export_results(reclist: wmatched + wextra_matches, ofile: OUTPUT_TITLELIST,
                 output_headers: OUTPUT_HEADERS,
                 custom_headers: titlelist_headers, mode: 'w')

  i = 0
  File.open(OUTPUT_TITLELIST_EXTRAS, 'w') do |f|
    wextra_matches.each do |record|
      f.write(i.to_s + "\n")
      f.write(record.print_extras(titlelist_headers) + "\n")
      i += 1
    end
  end

  titlelist_sorted_extras = []
  wextra_matches.each do |record|
    s = record.ss_match
    s_sorted = s.to_a.sort_by { |s|
      [s.most_recent_data[:modevalue], s.most_recent_data[:comparator]]
    }.reverse
    record.ss_match = s_sorted
    titlelist_sorted_extras << record
  end
  wextra_matches = nil
end

# RUN CHECKS
#
#
# gets enddate_descriptors for used sersol entries
all_end_date_descriptors = []
(mil_records.to_a + titlelist_records.to_a).each do |rec|
  next unless rec.all_entries
  rec.all_entries.each do |entry|
    all_end_date_descriptors << entry.enddate_descriptor
  end
end
File.write('CHECK_used_date_descriptors.txt',
           Set.new(all_end_date_descriptors.compact.sort).to_a.join("\n"))

# It's odd to have ssj's in Sierra/titlelist that aren't tracked
File.write('CHECK_ssjs_not_in_sersol_report.txt',
           Set.new($ssjs_not_in_sersol_report).to_a.join("\n"))
