require 'minitest/autorun'
require 'stringio'

require_relative '../lib/assembox'

Dir::chdir(File::join(File::dirname(__FILE__), "data"))

def make_mime_part(s)
  unless File::exists?(s)
    File::open(s, "w") { |fp| fp.puts "X-Test-Generated: Yes\n" }
  end
  MimePart.new(s)
end

def make_complex_message
  parts = %w(605242.HEADER 605242.1.MIME 605242.1.1.MIME 605242.1.1.1.MIME
       605242.1.1.1 605242.1.1.2.MIME 605242.1.1.2 605242.1.1.3.MIME
       605242.1.1.3 605242.1.2.MIME 605242.1.2 605242.1.3.MIME 605242.1.3
       605242.2.MIME 605242.2)
  x = parts.shuffle
  m = Message.new(make_mime_part(x.pop))
  x.each { |s| m << make_mime_part(s) }
  [m, parts]
end

describe MimePart do
  it "classifies plain messages" do
    p = make_mime_part("1.")
    p.type.must_equal :plain
    p.base.must_equal "1"
    p.path.must_equal "1"
  end

  it "classifies HEADER" do
    p = make_mime_part("562929.HEADER")
    p.type.must_equal :header
    p.base.must_equal "562929"
    p.path.must_equal "562929"
  end

  it "classifies MIME" do
    p = make_mime_part("1.2.3.MIME")
    p.type.must_equal :mime
    p.base.must_equal "1"
    p.path.must_equal "1.2.3"
  end

  it "classifies parts" do
    p = make_mime_part("411.2.3")
    p.type.must_equal :part
    p.base.must_equal "411"
    p.path.must_equal "411.2.3"
  end

  it "classifies TEXT" do
    p = make_mime_part("1.2.3.TEXT")
    p.type.must_equal :text
    p.base.must_equal "1"
    p.path.must_equal "1.2.3"
  end

  describe "compares" do
    it "header and header" do
      cmp "1.HEADER", "2.HEADER", -1
    end

    it "part and header" do
      cmp "667323.2", "667323.HEADER", 1
    end

    it "part and MIME" do
      cmp "120.2.MIME", "120.1", 1
    end

    it "plain and part" do
      cmp "570.", "570.1", -1
    end
  end

  def cmp(s1, s2, res)
    m1 = make_mime_part(s1)
    m2 = make_mime_part(s2)
    (m1 <=> m2).must_equal res
    (m2 <=> m1).must_equal (- res)
  end
end

describe Message do
  before do
    @mm = Message.new(make_mime_part("667323.1"))
    ["667323.1.MIME", "667323.2", "667323.2.MIME", "667323.HEADER"].each do |s|
      @mm << make_mime_part(s)
    end

    @mp = Message.new(make_mime_part("42."))
  end

  it "classifies MIME messages" do
    @mm.parts.size == 5
    @mm.mime?.must_equal true
    @mm.parts.sort.map { |p| p.name }.must_equal ["667323.HEADER",
       "667323.1.MIME", "667323.1", "667323.2.MIME", "667323.2"]
  end

  it "classifies plain messages" do
    @mp.plain?.must_equal true
  end

  it "sorts a complex message" do
    m, parts = make_complex_message
    m.parts.sort.map { |p| p.name }.must_equal parts
  end
end

describe HeaderReader do
  M1 = "Return-Path: joe@example.com\nMessage-ID: <foo bar>\n\n"
  M2 = "Content-Type: multipart/alternative;\n   boundary=0xdeadbeef\n\n"
  M3 = "Content-Type: multipart/mixed; Boundary=\"'dead' 'beef'!\""
  M4 = "conTent-tyPE: multipart/alternative;\n\tbOuNdary=deadbeef"

  before do
    @io1 = HeaderReader.new(StringIO.new(M1))
    @io2 = HeaderReader.new(StringIO.new(M2))
    @io3 = HeaderReader.new(StringIO.new(M3))
    @io4 = HeaderReader.new(StringIO.new(M4))
  end

  it "reads headers" do
    lines = @io1.lines
    lines.size.must_equal 2
    lines[0][:key].must_equal "return-path"
    lines[0][:value].must_equal "joe@example.com"
    lines[1][:key].must_equal "message-id"
    lines[1][:value].must_equal "<foo bar>"
  end

  it "reads multiline headers" do
    lines = @io2.lines
    lines.size.must_equal 1
    lines[0][:key].must_equal "content-type"
  end

  describe "scan" do
    it "finds plain boundary" do
      @io2.scan!
      @io2.boundary.must_equal "0xdeadbeef"
    end

    it "finds quoted boundary" do
      @io3.scan!
      @io3.boundary.must_equal "'dead' 'beef'!"
    end

    it "finds boundary continued with tab and funky capitalization" do
      @io4.scan!
      @io4.boundary.must_equal "deadbeef"
    end
  end
end

describe BoundaryStack do
  before do
    @msg, _ = make_complex_message
    @header = @msg.find(:header)
    @parts = @msg.parts.inject({}) do |h, p|
      h[p.name.gsub(/^605242\./, "")] = p
      h
    end
    @stack = BoundaryStack.new
    @stack.enter(@header)
    @stack.exit(@header)
  end

  it "boundary from header" do
    @stack.top.must_equal "Header"
  end

  it "boundary from child" do
    @stack.enter(@parts["1.MIME"])
    @stack.top.must_equal "Header"
    @stack.exit(@parts["1.MIME"])
    @stack.top.must_equal "rel-level1"
  end

  it "boundary for sibling" do
    @stack.enter(@parts["1.MIME"])
    @stack.top.must_equal "Header"
    @stack.exit(@parts["1.MIME"])
    @stack.top.must_equal "rel-level1"

    @stack.enter(@parts["1.1.MIME"])
    @stack.top.must_equal "rel-level1"
    @stack.exit(@parts["1.1.MIME"])
    @stack.top.must_equal "alt-level2"

    @stack.enter(@parts["1.1.1.MIME"])
    @stack.top.must_equal "alt-level2"
    @stack.exit(@parts["1.1.1.MIME"])
    @stack.top.must_equal "alt-level2"

    @stack.enter(@parts["1.1.2.MIME"])
    @stack.top.must_equal "alt-level2"
    @stack.exit(@parts["1.1.2.MIME"])
    @stack.top.must_equal "alt-level2"

    @stack.enter(@parts["1.2.MIME"])
    @stack.top.must_equal "rel-level1"
    @stack.exit(@parts["1.2.MIME"])
    @stack.top.must_equal "rel-level1"

    @stack.enter(@parts["2.MIME"])
    @stack.top.must_equal "Header"
    @stack.exit(@parts["2.MIME"])
    @stack.top.must_equal "Header"
  end
end
