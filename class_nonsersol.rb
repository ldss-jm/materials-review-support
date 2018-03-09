class NotSersolEntry
  attr_reader :title, :issn, :ssj, :all_issns, :_001
  attr_accessor :ss_match, :ss_match_by, :note, :scraped_issns

  def get_matches(sersol_by_ssj, issn_to_sersol, blacklist)
    if @ssj
      if sersol_by_ssj.include?(@ssj)
        @ss_match << sersol_by_ssj[@ssj]
        @ss_match_by << [@ssj, sersol_by_ssj[@ssj]]
      else
        if not blacklist.include?(@ssj)
          $ssjs_not_in_sersol_report << @ssj
          if not @note.include?('ssj not found in sersol report; ')
            @note += 'ssj not found in sersol report; '
          end
        end
      end
    end
    if not all_issns.empty?
      all_issns.each do |issn|
        if issn_to_sersol.include?(issn)
          issn_to_sersol[issn].each do |ss_by_issn|
            if @ss_match.include?(ss_by_issn)
              @ss_match << ss_by_issn
              @ss_match_by << [issn, ss_by_issn]
            else
              @ss_match << ss_by_issn
              @ss_match_by << [issn, ss_by_issn]
            end
          end
        end
      end
    end
  end

  def match_count()
    return @ss_match.length
  end
  
  def all_entries()
    entries = []
    if @ss_match.empty?
      return nil
    end
    @ss_match.to_a.each do |title|
      title.entries.each do |entry|
        entries << entry
      end
    end
    return entries
  end
  
  def print_output(headers)
    output = []
    headers.each do |header|
      output << @record[header]
    end
    output += [@ss_match.length]
    if @ss_match.length == 0
      if all_issns.empty? and not @ssj
        @note += 'Had no ssj/issn to make match; '
        return (output + [@note]).join("\t")
      else
        return (output + [@note]).join("\t")
      end
    elsif @ss_match.length > 1
      sersol = @ss_match.first
      _end = sersol.most_recent_end
      output += [@note,
                  all_issns.to_a.join(' | '),
                  sersol.ssj,
                  sersol.entries[0].title,
                  _end['mode'],
                  _end['date'],
                  _end['resource'],
                  ]      
      return output.join("\t")
    else
      sersol = @ss_match.first
      _end = sersol.most_recent_end
        output += [@note,
                  all_issns.to_a.join(' | '),
                  sersol.ssj,
                  sersol.entries[0].title,
                  _end['mode'],
                  _end['date'],
                  _end['resource'],
                  ]
        return output.join("\t")
    end    
  end
  
  def print_extras(headers)
    if @ss_match.length > 1
      output = []
      output << [print_output(headers)]
      sort_list = []
      @ss_match.to_a.each do |ssj|
        sort_list << [ssj.most_recent_end['mode'], ssj.most_recent_end['comparator'],
                      ssj]
      end
      # This is bad sorting: We want to sort by ASC end_mode (current<embargo<fixed)
      # and then DESC date (to get the most recent). So we're sorting by the last
      # letter of the end_mode and date, then reversing. Hope we don't add an
      # end_mode.
      #
      sort_list.sort_by { |a| [ a[0][-1], a[1]] }.reverse.each do |title|
        ssj = title[2]
        _end = ssj.most_recent_end
        ss_line = ['',
                   _end['resource'],   
                   _end['mode'],
                   _end['date'],
                   ssj.entries[0].title,
                   ssj.all_issns.to_a.join(' | '),
                   ssj.ssj
                   ]
        output << ss_line.join("\t")
      end
      return output.join("\n") + "\n\n"
    end
  end
end


class MilEntry < NotSersolEntry
  
  def initialize(hsh)
    @record = hsh
    @note = ''
    #@title = hsh['title']
    #@_001 = blah for ssj
    #@issn = hsh['issn']
    @title = hsh['245']
    @_001 = hsh['1']
    if false # true = use unified 22 field
      @_022 = hsh['22']
    else
      @_022a = hsh['022|a']
      @_022L = hsh['022|l']
      @_022y = hsh['022|y']
      @_022 = [@_022a, @_022L].join(' ')
    end
    @_776 = hsh['776|x']
    @ss_match = Set.new()
    @ss_match_by = []
    if @_001.start_with?('ss')
      @ssj = @_001
    end
  end
  
  #needs issns(all)
  def all_issns()
    return @all_issns_store ||= gen_all_issns
  end
  
  def gen_all_issns()
    if @_776.split(";")
      @all_issns_store = Set.new(@_776.split(";"))
    end
    @_022.split(" ").each do |entry|
      if entry.length > 1
        @all_issns_store << entry
      end
    end
    if @scraped_issns
      @all_issns_store += @scraped_issns
    end
    return @all_issns_store
  end
  
  def add_022y()
    if not @_022y.empty?
      @all_issns_store << @_022y
    end
  end
  
  def scrape_issns(api)
    if @_001.empty?
      return nil
    end
    if @scraped_issns
      return @scraped_issns
    end
    if @_001.match(/^[0-9]+/)
      #puts @_001
      api.read_bib(@_001)
      #scrapes 776|x and 022|a, 022|l, but not 022|y
      issns = []
      if api.bib.include?('776')
        api.bib['776'].each do |tag|
          tag['subfieldItems'].each do |subfield|
            if subfield['subfieldCode'] == 'x'
              issns << subfield['data']
            end
          end
        end
      end
      if api.bib.include?('022')
        api.bib['022'].each do |tag|
          tag['subfieldItems'].each do |subfield|
            if subfield['subfieldCode'] == 'a'
              issns << subfield['data']
            elsif subfield['subfieldCode'] == 'l'
              issns << subfield['data']
            end
          end
        end
      end
      @scraped_issns = Set.new(issns)
      return @scraped_issns
    end
  end
  
end
#one_match[0].print_output(mil_headers)


class WileyEntry < NotSersolEntry
  
  def initialize(hsh)
    @record = hsh
    @note = ''
    @title = hsh['title']
    @issn = hsh['issn']
    @eissn = hsh['eissn']
    @ss_match = Set.new()
    @ss_match_by = []
    if not hsh.include?('ssj#') and hsh['ssj#'].start_with?('ss')
      @ssj = hsh['ssj#']
    end
  end
  
  #needs issns(all)
  def all_issns()
    @all_issns = Set.new()
    if @issn
      @all_issns << @issn
    end
    if @eissn
      @all_issns << @issn
    end
    return @all_issns
  end
  
end
