require 'set'

class NotSersolEntry
  # Sierra (or titlelist/other) records for which we'd like to find
  # matching SersolTitle(s). Subclassed by the type of record.

  attr_reader :title, :issn, :ssj, :all_issns, :_001, :record
  attr_accessor :ss_match, :ss_match_by, :note, :scraped_issns

  def get_matches(sersol_by_ssj, issn_to_sersol, blacklist)
    if @ssj
      if sersol_by_ssj.include?(@ssj)
        @ss_match << sersol_by_ssj[@ssj]
        @ss_match_by << [@ssj, sersol_by_ssj[@ssj]]
      elsif !blacklist.include?(@ssj)
        $ssjs_not_in_sersol_report << @ssj
        unless @note.include?('ssj not found in sersol report; ')
          @note += 'ssj not found in sersol report; '
        end
      end
    end

    all_issns.each do |issn|
      next unless issn_to_sersol.include?(issn)
      issn_to_sersol[issn].each do |ss_by_issn|
        @ss_match << ss_by_issn
        @ss_match_by << [issn, ss_by_issn]
      end
    end
  end

  def filter_bad_issns(issn)
    bad_issns = ['', '-', '0']
    return nil if bad_issns.include?(issn)
    issn
  end

  def match_count
    @ss_match.length
  end

  def all_entries
    return nil if @ss_match.empty?
    entries = []
    @ss_match.to_a.each do |title|
      title.entries.each { |entry| entries << entry }
    end
    entries
  end

  def print_output(headers)
    output = headers.map { |h| @record[h] }
    output << @ss_match.length
    if @ss_match.empty?
      @note += 'Had no ssj/issn to make match; ' if all_issns.empty? && !@ssj
      output << @note
    else
      sersol = @ss_match.first
      output += [@note,
                 all_issns.to_a.join(' | '),
                 sersol.ssj,
                 sersol.entries.first.title]
      # output += SersolTitle.out_data(sersol, sersol.entries) # full data
      output += SersolTitle.out_data(sersol, sersol.paid) # paid data
      output += SersolTitle.out_data(sersol, sersol.free) # free data
    end
    output.join("\t")
  end

  def print_extras(headers)
    return nil unless @ss_match.length > 1
    output = []
    output << [print_output(headers)]
    sort_list = @ss_match.map do |ssj|
      [ssj.most_recent_data[:modevalue], ssj.most_recent_data[:comparator], ssj]
    end
    sort_list.sort_by { |a| [a[0], a[1]] }.reverse_each do |title|
      sersol = title[2]
      ss_line = [
        '',
        sersol.entries[0].title,
        sersol.ssj,
        sersol.all_issns.to_a.join(' | '),
        ''
      ]
      ss_line += SersolTitle.out_data(sersol, sersol.entries) # full data
      ss_line += [
        sersol.all_issns.to_a.join(' | '),
        sersol.ssj,
        sersol.entries[0].title
      ]
      # ss_line += SersolTitle.out_data(sersol, sersol.entries) # full data again
      ss_line += SersolTitle.out_data(sersol, sersol.paid) # paid data
      ss_line += SersolTitle.out_data(sersol, sersol.free) # free data
      output << ss_line.join("\t")
    end
    output.join("\n") + "\n\n"
  end
end

class MilEntry < NotSersolEntry
  attr_accessor :all_issns

  def initialize(hsh)
    @record = hsh
    @note = ''
    @title = hsh['245']
    @_001 = hsh['001']
    @_022a = clean_incoming_isbns(hsh['022|a'])&.split(' ')
    @_022L = clean_incoming_isbns(hsh['022|l'])&.split(' ')
    @_022y = clean_incoming_isbns(hsh['022|y'])&.split(' ')
    @_776 = clean_incoming_isbns(hsh['776|x'])&.split(' ')
    @ss_match = Set.new
    @ss_match_by = []
    @ssj = @_001 if @_001&.start_with?('ss')
  end

  # collapse consecutive whitespace and double-quotes from isbn strings]
  # isbn strings resemble: 0098-9053
  #                    or: 0098-9053 "0013-9947"
  def clean_incoming_isbns(isbn_string)
    return unless isbn_string
    isbn_string.tr('"', ' ').
                tr(';', ' ').
                gsub(/\s\s+/, ' ')
  end

  def all_issns
    @all_issns ||= gen_all_issns
  end

  def gen_all_issns
    @all_issns = Set.new([@_022a, @_022L, @_776].flatten.compact)
  end

  def add_scraped_issns
    return unless @scraped_issns
    @all_issns += @scraped_issns
  end

  def add_022y
    return unless @_022y
     @_022y.each { |i| @all_issns << i }
  end

  # scrapes 776|x and 022|a, 022|L, but not 022|y
  def scrape_issns(api)
    return @scraped_issns if @scraped_issns
    return nil if @_001.nil? || @_001 !~ /^[0-9]+/
    puts "001: #{@_001}"
    api.read_bib(@_001)
    issns = Set.new
    api.bib&.fields('776')&.each do |field|
      field.subfields.each do |sf|
        issns << sf.value if sf.code == 'x'
      end
    end
    api.bib&.fields('022')&.each do |field|
      field.subfields.each do |sf|
        issns << sf.value if %w[a l].include?(sf.code)
      end
    end
    @scraped_issns = issns
  end
end

class TitlelistEntry < NotSersolEntry
  def initialize(hsh)
    @record = hsh
    @note = ''
    @title = hsh['title']
    # @issn = hsh['issn']      # srp17
    # @eissn = hsh['e-issn']   # srp17
    @issn = filter_bad_issns(hsh['issn1'].to_s.strip)
    @eissn = filter_bad_issns(hsh['issn2'].to_s.strip)
    @ss_match = Set.new
    @ss_match_by = []
    @ssj = hsh['ssj#'] if hsh['ssj#']&.start_with?('ss')
  end

  def all_issns
    [@issn, @eissn].uniq.compact
  end
end
