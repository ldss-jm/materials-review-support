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
      else
        unless blacklist.include?(@ssj)
          $ssjs_not_in_sersol_report << @ssj
          unless @note.include?('ssj not found in sersol report; ')
            @note += 'ssj not found in sersol report; '
          end
        end
      end
    end
    all_issns.each do |issn|
      if issn_to_sersol.include?(issn)
        issn_to_sersol[issn].each do |ss_by_issn|
          @ss_match << ss_by_issn
          @ss_match_by << [issn, ss_by_issn]
        end
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
    if @ss_match.length == 0
      if all_issns.empty? and not @ssj
        @note += 'Had no ssj/issn to make match; '
      end
      output << @note
    else
      sersol = @ss_match.first
      full_data = sersol.most_recent_data
      full_resources = sersol.most_recent&.map { |r| r.resource }
      full_resources ||= []
      full_resources = full_resources.join(' | ')
      # free_data = sersol.most_recent_data(only_free: true)
      # free_resources = sersol.most_recent(only_free: true)&.map { |r| r.resource }
      # free_resources ||= []
      # free_resources = free_resources.join(' | ')
      output += [@note,
                all_issns.to_a.join(' | '),
                sersol.ssj,
                sersol.entries[0].title,
                full_data[:mode].to_s,
                full_data[:date].to_s,
                full_resources.to_s,
                # free_data[:mode].to_s,
                # free_data[:date].to_s,
                # free_resources.to_s,
                ]
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
    # sort by (modevalue, end_date) DESC
    sort_list.sort_by { |a| [ a[0], a[1] ] }.reverse.each do |title|
      sersol = title[2]
      full_data = sersol.most_recent_data
      full_resources = sersol.most_recent&.map { |r| r.resource }
      full_resources ||= []
      full_resources = full_resources.join(' | ')
      # free_data = sersol.most_recent_data(only_free: true)
      # free_resources = sersol.most_recent(only_free: true)&.map { |r| r.resource }
      # free_resources ||= []
      # free_resources = free_resources.join(' | ')
      ss_line = [
        '',
        sersol.entries[0].title,
        sersol.ssj,
        sersol.all_issns.to_a.join(' | '),
        '',
        full_data[:mode].to_s,
        full_data[:date].to_s,
        full_resources.to_s,
        sersol.all_issns.to_a.join(' | '),
        sersol.ssj,
        sersol.entries[0].title,
        full_data[:mode].to_s,
        full_data[:date].to_s,
        full_resources.to_s
        # free_resources.to_s, 
        # free_data[:mode].to_s,
        # free_data[:date].to_s,
      ]
      output << ss_line.join("\t")
    end
    return output.join("\n") + "\n\n"
  end
end


class MilEntry < NotSersolEntry
  
  attr_accessor :all_issns

  def initialize(hsh)
    @record = hsh
    @note = ''
    @title = hsh['245']
    @_001 = hsh['1']
    @_022a = hsh['022|a'].gsub(/\s\s+/, ' ').split(' ')
    @_022L = hsh['022|l'].gsub(/\s\s+/, ' ').split(' ')
    @_022y = hsh['022|y'].gsub(/\s\s+/, ' ').split(' ')
    @_776 = hsh['776|x'].split(";")
    @ss_match = Set.new()
    @ss_match_by = []
    @ssj = @_001 if @_001.start_with?('ss')
  end
  
  def all_issns
    @all_issns ||= gen_all_issns
  end
  
  def gen_all_issns
    @all_issns = Set.new([@_022a, @_022L, @_776].flatten)
  end

  def add_scraped_issns
    @all_issns += @scraped_issns
  end
  
  def add_022y
    @all_issns_store << @_022y unless @_022y.empty?
  end
  
  #scrapes 776|x and 022|a, 022|L, but not 022|y
  def scrape_issns(api)
    return @scraped_issns if @scraped_issns
    return nil if @_001.empty? || @_001 !~ (/^[0-9]+/)
    api.read_bib(@_001)
    issns = []
    if api.bib.include?('776')
      api.bib['776'].each do |tag|
        tag['subfieldItems'].each do |sf|
          issns << sf['data'] if sf['subfieldCode'] == 'x'
        end
      end
    end
    if api.bib.include?('022')
      api.bib['022'].each do |tag|
        tag['subfieldItems'].each do |sf|
          issns << sf['data'] if ['a', 'l'].include?(sf['subfieldCode'])
        end
      end
    end
    @scraped_issns = Set.new(issns)
  end
end

class TitlelistEntry < NotSersolEntry
  
  def initialize(hsh)
    @record = hsh
    @note = ''
    @title = hsh['title']
    #@issn = hsh['issn']      # srp17
    #@eissn = hsh['e-issn']   # srp17
    @issn = filter_bad_issns(hsh['issn1'].strip)
    @eissn = filter_bad_issns(hsh['issn2'].strip)
    @ss_match = Set.new()
    @ss_match_by = []
    @ssj = hsh['ssj#'] if hsh['ssj#']&.start_with?('ss')
  end
  
  def all_issns
    [@issn, @eissn].uniq.compact
  end
  
end
