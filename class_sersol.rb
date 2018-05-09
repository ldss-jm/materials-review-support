require 'date'
require 'set'

#sersol_file input needs to be tab-delim

class SersolEntry

  # A SerSol resource / access point. Is associated with a particular
  # SersolTitle (ssj/title)

  attr_reader :ssj, :title, :issn, :eissn, :enddate_descriptor,:enddate, 
              :end_mode, :resource
  
  def initialize(hsh)
    @ssj = hsh['id']
    @title = hsh['title']
    @issn = hsh['issn']
    @eissn = hsh['eissn']
    @startdate = hsh['startdate']
    @enddate_descriptor = hsh['enddate']
    @resource = hsh['resource']
    @url = hsh['url']
    #@whitelist = hsh['include as alt access point?']  # srp17
    @whitelist = hsh['include/exclude']
    #@free_ind =hsh['freely available']  # data not requested
  end

  def is_free?
    # data not requested
    #raise 'free_ind must be yes/no' unless %w(yes no).include?(@free_ind)
    if @free_ind == 'yes'
      true
    else
      false
    end
  end

  def blacklisted
    include_me = @whitelist.downcase
    #return true if include_me == 'no'                            # srp17
    #raise 'whitelist must be yes/no' unless include_me == 'yes'  # srp17
    return true if include_me == 'exclude'
    raise 'whitelist must be yes/no' unless include_me == 'include'
    false
  end
  
  def enddate
    return '' unless @enddate_descriptor
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
      return 'error: ' + @enddate_descriptor
    end
  end

  def end_mode
    return @endmode if @endmode
    if @enddate_descriptor == ''
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
    @endmode
  end

  def embargo_text
    return nil unless end_mode == 'embargo'
    return @enddate_descriptor if @enddate_descriptor.include?('ago')
    years = (Time.now.year - enddate.year)
    if years == 1
      return years.to_s + ' year ago'
    else
      return years.to_s + ' years ago'
    end
  end

  def embargo_comparator
    return nil unless end_mode == 'embargo'
    return enddate unless @enddate_descriptor.include?('ago')
    days = case @enddate_descriptor.downcase
           when /year/ then 365
           when /month/ then 30
           when /week/ then 7
           when /day/ then 1
           end
    quantity = @enddate_descriptor.match(/^[^0-9]*([0-9]*)/)[1]
    return Date.today - (days * quantity.to_i)
  end
  
end

class SersolTitle

  # A unique title (generally a distinct ssj). Collects any
  # SersolEntry objects (resources / access points) for the title. Primarily
  # to compare the SersolEntries and find the "best" one.

  attr_reader :ssj
  attr_accessor :entries

  def initialize(ssj)
    @ssj = ssj
    @entries = []
  end
  

  

  def current_ends(restrictions)
    e = @entries.dup
    if restrictions[:only_free]
      e.select! { |x| x.is_free? }
    end
    e.select! { |x| x.end_mode == 'current'}
    return e unless e.empty?
  end

  def embargo_ends(restrictions)
    e = @entries.dup
    if restrictions[:only_free]
      e.select! { |x| x.is_free? }
    end
    e.select! { |x| x.end_mode == 'embargo'}
    return e unless e.empty?
  end

  def fixed_ends(restrictions)
    e = @entries.dup
    if restrictions[:only_free]
      e.select! { |x| x.is_free? }
    end
    e.select! { |x| x.end_mode == 'fixed'}
    return e unless e.empty?
  end

  def most_recent(restrictions=nil)
    restrictions ||= {}
    most_recent = nil
    if self.current_ends(restrictions)
      most_recent = self.current_ends (restrictions)
    elsif self.embargo_ends(restrictions)
      ends = self.embargo_ends(restrictions)
      a_max_entry = ends.max { |a,b| a.embargo_comparator <=> b.embargo_comparator }
      max_value = a_max_entry.embargo_comparator
      most_recent = ends.select { |x| x.embargo_comparator == max_value }
    elsif self.fixed_ends(restrictions)
      ends = self.fixed_ends(restrictions)
      a_max_entry = ends.max { |a,b| a.enddate <=> b.enddate }
      max_value = a_max_entry.enddate
      most_recent = ends.select { |x| x.enddate == max_value}
    end
    most_recent
  end

  def most_recent_data(restrictions=nil)
    restrictions ||= {}
    modevalue = { 'current' => 3, 'embargo' => 2, 'fixed' => 1 }
    best = self.most_recent(restrictions)&.first # best or tied for best
    unless best
      return {mode: nil, modevalue: nil, comparator: nil, date: nil}
    end
    if best.end_mode == 'current'
      mode = 'current'
      comparator = 'current'
    elsif best.end_mode == 'embargo'
      mode = 'embargo'
      comparator = best.embargo_comparator
      date = best.embargo_text
    elsif best.end_mode == 'fixed'
      mode = 'fixed'
      comparator = best.enddate
    end
    date ||= comparator
    return {mode: mode, modevalue: modevalue[mode], comparator: comparator, date: date}
  end

#  def most_recent_end()
#    fixed_ends = []
#    embargo_ends = []
#    current_resources = []
#    @entries.each do |entry|
#      if entry.end_mode == 'current'
#        current_resources << entry.resource
#      elsif entry.end_mode == 'embargo'
#        embargo_ends << {'date' => entry.embargo_text,
#                         'comparator' => entry.embargo_comparator,
#                         'resource' => entry.resource,
#                         'mode' => 'embargo'}
#      else
#        fixed_ends << {'date' => entry.enddate,
#                       'resource' => entry.resource,
#                       'mode' => 'fixed'}
#      end
#    end
#    if not current_resources.empty?
#      return {'date' => 'current',
#              'comparator' => 'current',
#              'resource' => current_resources.join(" | "),
#              'mode' => 'current'}
#    elsif not embargo_ends.empty?
#      #return embargo_ends.max {|a,b| a['comparator'] <=> b['comparator']}
#      maxentry = embargo_ends.max {|a,b| a['comparator'] <=> b['comparator']}
#      maxdate = maxentry['comparator']
#      resources = []
#      embargo_ends.each do |entry|
#        if entry['comparator'] == maxdate
#          resources << entry['resource']
#        end
#      end
#      return {'date' => maxentry['date'],
#              'comparator' => maxentry['comparator'],
#              'resource' => resources.join(" | "),
#              'mode' => 'embargo'}
#    else
#      #return fixed_ends.max {|a,b| a['date'] <=> b['date']}
#      maxentry = fixed_ends.max {|a,b| a['date'] <=> b['date']}
#      maxdate = maxentry['date']
#      resources = []
#      fixed_ends.each do |entry|
#        if entry['date'] == maxdate
#          resources << entry['resource']
#        end
#      end
#      return {'date' => maxentry['date'],
#              'comparator' => maxentry['date'],
#              'resource' => resources.join(" | "),
#              'mode' => 'fixed'}
#    end
#  end
  
  def all_issns()
    issns = Set.new()
    @entries.each do |entry|
      issns << entry.issn
      issns << entry.eissn
    end
    return issns.delete("")
  end
  
end
