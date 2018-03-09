require 'date'
require 'set'

#sersol_file input needs to be tab-delim

class SersolEntry
  attr_reader :ssj, :title, :issn, :eissn, :enddate_descriptor,:enddate, :end_mode, :resource, :blacklisted
  #attr_accessor :blacklisted
  
  def initialize(hsh)
    @ssj = hsh['id']
    @title = hsh['title']
    @issn = hsh['issn']
    @eissn = hsh['eissn']
    @startdate = hsh['startdate']
    @enddate_descriptor = hsh['enddate']
    @resource = hsh['resource']
    @url = hsh['url']
    @whitelist = hsh['include as alt access point?']
    @blacklisted = @whitelist.downcase == 'no'
  end
  
  def enddate
    if not @enddate_descriptor
      return ''
    else
      begin
        date_helper = (@enddate_descriptor.gsub('Fall ', '9/20/')
                                          .gsub('Winter ', '12/20/')
                                          .gsub('Spring ', '3/20/')
                                          .gsub('Summer ', '6/20/')
                                          )
        return Date.strptime(date_helper, '%m/%d/%Y')
      rescue ArgumentError
        begin
          return Date.strptime(@enddate_descriptor, '%Y')
        rescue ArgumentError
          return 'error' + @enddate_descriptor
        end
      end
    end
  end

  def end_mode()
    if @endmode
      return @endmode
    elsif @enddate_descriptor == ''
      @endmode = 'current'
    elsif @enddate_descriptor.downcase.include?('current')
      @endmode = 'current'
    elsif @enddate_descriptor.include?('ago')
      @endmode = 'embargo'
    elsif @resource.downcase.include?('jstor')
      @endmode = 'embargo'
    else
      @endmode = 'fixed'
    end
    return @endmode
  end

  def embargo_text()
    if end_mode == 'embargo'
      if @enddate_descriptor.include?('ago')
        return @enddate_descriptor
      else
        #puts enddate
        years = (2017 - enddate.year)
        if years == 1
          return years.to_s + ' year ago'
        else
          return years.to_s + ' years ago'
        end
      end
    end
    return nil
  end

  def embargo_comparator()
    if end_mode == 'embargo'
      if @enddate_descriptor.include?('ago')
        days = case @enddate_descriptor.downcase
                 when /year/ then 365
                 when /month/ then 30
                 when /week/ then 7
                 when /day/ then 1
               end
        quantity = @enddate_descriptor.match(/^[^0-9]*([0-9]*)/)[1]
        #puts @enddate_descriptor
        return Date.today - (days * quantity.to_i)
      else
        return enddate
      end
    end
    return nil
  end
  
end

class SersolTitle
  attr_reader :ssj
  attr_accessor :entries

  def initialize(ssj)
    @ssj = ssj
    @entries = []
  end
  

  
  def most_recent_end()
    fixed_ends = []
    embargo_ends = []
    current_resources = []
    @entries.each do |entry|
      if entry.end_mode == 'current'
        current_resources << entry.resource
      elsif entry.end_mode == 'embargo'
        embargo_ends << {'date' => entry.embargo_text,
                         'comparator' => entry.embargo_comparator,
                         'resource' => entry.resource,
                         'mode' => 'embargo'}
      else
        fixed_ends << {'date' => entry.enddate,
                       'resource' => entry.resource,
                       'mode' => 'fixed'}
      end
    end
    if not current_resources.empty?
      return {'date' => 'current',
              'comparator' => 'current',
              'resource' => current_resources.join(" | "),
              'mode' => 'current'}
    elsif not embargo_ends.empty?
      #return embargo_ends.max {|a,b| a['comparator'] <=> b['comparator']}
      maxentry = embargo_ends.max {|a,b| a['comparator'] <=> b['comparator']}
      maxdate = maxentry['comparator']
      resources = []
      embargo_ends.each do |entry|
        if entry['comparator'] == maxdate
          resources << entry['resource']
        end
      end
      return {'date' => maxentry['date'],
              'comparator' => maxentry['comparator'],
              'resource' => resources.join(" | "),
              'mode' => 'embargo'}
    else
      #return fixed_ends.max {|a,b| a['date'] <=> b['date']}
      maxentry = fixed_ends.max {|a,b| a['date'] <=> b['date']}
      maxdate = maxentry['date']
      resources = []
      fixed_ends.each do |entry|
        if entry['date'] == maxdate
          resources << entry['resource']
        end
      end
      return {'date' => maxentry['date'],
              'comparator' => maxentry['date'],
              'resource' => resources.join(" | "),
              'mode' => 'fixed'}
    end
  end
  
  def all_issns()
    issns = Set.new()
    @entries.each do |entry|
      issns << entry.issn
      issns << entry.eissn
    end
    return issns.delete("")
  end
  
end
