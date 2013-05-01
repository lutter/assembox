#! /usr/bin/ruby

def warn(s)
  $stderr.puts "WARN: #{s}"
end

class HeaderReader
  attr_reader :from, :message_id, :boundary

  def initialize(io)
    @io = io
  end

  def gets
    line = next_line
    return nil if line.nil?
    line.strip!
    cont = true
    while cont && l = next_line
      if l[0] == " " || l[0] == "\t"
        line = "#{line} #{l.strip}"
      else
        unget_line(l)
        cont = false
      end
    end
    a = line.split(":")
    { key: a.shift.downcase, value: a.join(":").strip }
  end

  def lines
    result = []
    while l = gets
      result << l
    end
    result
  end

  # Look for certain headers
  def scan!
    while l = gets
      if l[:key] == "content-type"
        if l[:value] =~ /; boundary="([^"]*)"/i
          @boundary = $1
        elsif l[:value] =~ /; boundary=([^ "]+)/i
          @boundary = $1
        end
      elsif l[:key] == "from"
        @from = l[:value]
      elsif l[:key] == "message-id"
        @message_id = l[:value]
      end
    end
  end

  private
  def next_line
    if @buf
      b = @buf
      @buf = nil
    elsif ! @io.nil?
      b = @io.gets
      if b == "\n"
        @io = nil
        b = nil
      end
    else
      b = nil
    end
    b
  end

  def unget_line(l)
    raise "ALready have buf" if @buf
    @buf = l
  end
end

class MimePart
  attr_reader :base, :type, :name, :path, :headers
  attr_reader :from, :message_id, :boundary

  def initialize(s)
    @name = s
    if s =~ /^([0-9]+)\.$/
      @base = $1
      @path = @base
      @type = :plain
    elsif s =~ /^([0-9]+)(\.[0-9]+)*$/
      @base = $1
      @path = s
      @type = :part
    elsif s =~ /^(([0-9]+)(\.[0-9.]*)?)(\.(MIME|HEADER|TEXT))$/
      @path = $1
      @base = $2
      if $5 == "MIME"
        @type = :mime
      elsif $5 == "HEADER"
        @type = :header
      elsif $5 == "TEXT"
        @type = :text
      else
        raise "Can not happen: #{s} #{$3.inspect}"
      end
    else
      raise "Whoa: #{s}"
    end
    if [:plain, :mime, :header].include?(@type)
      File::open(s, "r") do |fp|
        h = HeaderReader.new(fp)
        h.scan!
        @from = h.from || "Fake Sender <fake@example.org>"
        @message_id = h.message_id
        @boundary = h.boundary
      end
      if @type == :header && @boundary.nil?
        warn "No boundary for #{@name}"
      end
    end
  end

  def <=>(o)
    if base != o.base
      base <=> o.base
    else
      if type == :header
        -1
      elsif o.type == :header
        1
      else
        # Type must by Mime or Part
        if path == o.path
          if type == :mime && o.type == :part
            -1
          elsif type == :part && o.type == :mime
            1
          else
            raise "Duplicate for #{path}: #{type} #{o.type}"
          end
        else
          path <=> o.path
        end
      end
    end
  end

  def to_mbox(io, boundary)
    if type == :header
      io.puts "From #{@from}"
      append_to(io)
    elsif type == :plain
      io.puts "From #{@from}"
      append_to(io)
    elsif type == :part || type == :text
      append_to(io)
    elsif type == :mime
      io.puts "--#{boundary}" if boundary
      append_to(io)
    else
      raise "No output for #{self}"
    end
  end

  private
  def append_to(io)
    File::open(@name, "r") do |fp|
      s = fp.read
      io.write(s)
      if s[-2] != "\n" || s[-1] != "\n"
        io.write("\n\n")
      end
    end
  end
end

class BoundaryStack
  def initialize
    @stack = []
  end

  def top
    if @stack[0]
      @stack[0].boundary
    end
  end

  def enter(p)
    if p.type == :mime && !child?(@stack[0], p)
      @stack.shift
    end
  end

  def exit(p)
    if p.type == :header
      @stack = [ p ]
    elsif p.type == :mime && p.boundary
      @stack.unshift(p)
    end
  end

  private
  # Is P2 a child of P1 ?
  def child?(p1, p2)
    return true if p1.type == :header
    s1 = p1.name.gsub(".MIME", "")
    s2 = p2.name.gsub(".MIME", "")
    s2.start_with?(s1)
  end
end

# Possible message types:
# Plain
# Header, [Mime*, Part]*
# Header, Text
class Message
  attr_reader :base, :parts, :files

  def initialize(p)
    @parts = [ p ]
    @files = [ p.name ]
  end

  def <<(p)
    @files << p.name
    @parts << p
  end

  def find(type)
    @parts.find { |p| p.type == type }
  end

  def plain?
    @parts.size == 1 && @parts.first.type == :plain
  end

  def mime?
    @parts.any? { |p| p.type == :header }
  end

  def to_mbox(io)
    stack = BoundaryStack.new
    parts.sort.each do |p|
      stack.enter(p)
      p.to_mbox(io, stack.top)
      stack.exit(p)
    end
  end
end

class MessageList
  attr_reader :messages

  def initialize
    @messages = {}
  end

  def [](k)
    @messages[k]
  end

  def keys
    @messages.keys
  end

  def add(s)
    p = MimePart.new(s)
    if @messages[p.base]
      @messages[p.base] << p
    else
      @messages[p.base] = Message.new(p)
    end
  end

  def to_mbox(io)
    count = 0
    files = []
    messages.keys.sort.each do |k|
      m = messages[k]
      m.to_mbox(io)
      files << m.files
      count += 1
    end
    [count, files]
  end

  def finalize
    toadd = []
    @messages.values.each do |m|
      if (plain = m.find(:plain)) && m.parts.size > 1
        if h = m.find(:header)
          if h.message_id == plain.message_id
            m.parts.reject! { |p| p != plain }
          else
            m.parts.delete(plain)
            toadd << plain
          end
        else
          raise "Funky duplicates for #{m.inspect}"
        end
      end
    end
    toadd.each { |m| @messages["#{m.base}:plain"] = Message.new(m) }
  end
end
