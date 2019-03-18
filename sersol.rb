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
    @whitelist_data = hsh['include/exclude']
    @free_data = hsh['freely available']
  end

  # true when this is a resource E-res Acq does not want to be considered
  # as an alt-access point
  def blacklisted
    case @whitelist_data&.downcase
    when 'exclude'
      true
    when 'include'
      false
    else
      raise "invalid whitelist value: #{@whitelist_data}"
    end
  end

  # true when this is a resource E-res Acq has identified as free.
  # false when this is a resource E-res Acq has identified as paid.
  # free/paid are the only possible values.
  def free?
    case @free_data&.downcase
    when 'free'
      true
    when 'paid'
      false
    else
      raise 'status is neither free nor paid'
    end
  end

  def current?
    end_mode == 'current'
  end

  def embargo?
    end_mode == 'embargo'
  end

  def fixed?
    end_mode == 'fixed'
  end

  # Converts enddate_descriptor into Date object.
  def enddate
    return '' unless @enddate_descriptor
    date_helper = @enddate_descriptor.gsub('Fall ', '9/20/').
                                      gsub('Winter ', '12/20/').
                                      gsub('Spring ', '3/20/').
                                      gsub('Summer ', '6/20/')
    return Date.strptime(date_helper, '%m/%d/%Y')
  rescue ArgumentError
    begin
      return Date.strptime(@enddate_descriptor, '%Y')
    rescue ArgumentError
      return 'error: ' + @enddate_descriptor
    end
  end

  # Returns current/embargo/fixed.
  # JSTOR dates are always considered to be embargos.
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

  # Converts embargo enddates into 'x year(s) ago' format
  def embargo_text
    return unless end_mode == 'embargo'
    return @enddate_descriptor if @enddate_descriptor.include?('ago')
    years = (Time.now.year - enddate.year)
    if years == 1
      return years.to_s + ' year ago'
    else
      return years.to_s + ' years ago'
    end
  end

  def embargo_comparator
    return unless end_mode == 'embargo'
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

  # Filters the SersolTitle's entries (or provided list of entries) to
  # only current entries.
  def current(entries = @entries)
    mode_filter('current', entries)
  end

  # Filters the SersolTitle's entries (or provided list of entries) to
  # only embargo entries.
  def embargo(entries = @entries)
    mode_filter('embargo', entries)
  end

  # Filters the SersolTitle's entries (or provided list of entries) to
  # only fixed-end entries.
  def fixed(entries = @entries)
    mode_filter('fixed', entries)
  end

  def mode_filter(mode, entries)
    e = entries.dup
    e.select! { |x| x.end_mode == mode }
    return e unless e.empty?
  end

  # Filters the SersolTitle's entries (or provided list of entries) to
  # only free (i.e. not paid) entries.
  def free(entries = @entries)
    e = entries.dup
    e.select! { |x| x.free? }
    return e unless e.empty?
  end

  # Filters the SersolTitle's entries (or provided list of entries) to
  # only free (i.e. not free) entries.
  def paid(entries = @entries)
    e = entries.dup
    e.reject! { |x| x.free? }
    return e unless e.empty?
  end

  # Provides a list of SerSolEntries with the most-recent end
  def most_recent(entries = @entries)
    most_recent = nil
    if current(entries)
      most_recent = current(entries)
    elsif embargo(entries)
      ends = embargo(entries)
      a_max_entry = ends.max { |a,b| a.embargo_comparator <=> b.embargo_comparator }
      max_value = a_max_entry.embargo_comparator
      most_recent = ends.select { |x| x.embargo_comparator == max_value }
    elsif fixed(entries)
      ends = fixed(entries)
      a_max_entry = ends.max { |a,b| a.enddate <=> b.enddate }
      max_value = a_max_entry.enddate
      most_recent = ends.select { |x| x.enddate == max_value}
    end
    most_recent
  end

  # Provides a list of SerSolEntries with the most-recent end -- free only
  def most_recent_free
    most_recent(entries.select(&:free?))
  end

  # Provides a list of SerSolEntries with the most-recent end -- paid only
  def most_recent_paid
    most_recent(entries.reject(&:free?))
  end

  def most_recent_data(entries = @entries)
    modevalue = { 'current' => 3, 'embargo' => 2, 'fixed' => 1 }
    best = most_recent(entries)&.first # best or tied for best
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

  def all_issns()
    issns = Set.new()
    @entries.each do |entry|
      issns << entry.issn
      issns << entry.eissn
    end
    return issns.delete("")
  end

  def self.out_data(sersol, entries = @entries)
    data = sersol.most_recent_data(entries)
    resources = sersol.most_recent(entries)&.map { |r| r.resource } || []
    resources = resources.join(' | ')
    [
      data[:mode].to_s,
      data[:date].to_s,
      resources.to_s
    ]
  end

  def self.out_headers(suffix=nil)
    h = ['best_type', 'best_data', 'best_resources']
    h.map! { |s| "#{s}_#{suffix}" } if suffix
    h
  end

end
