# This loads a bunch of files and verifies that the dumped version matches the
# loaded version
#
# To avoid problems with whitespaces, the input file is reformatted before being
# compared
#
require 'typestore'
require 'typestore/io/xml_importer'
require 'typestore/io/xml_exporter'
require 'typestore/cxx'
require 'tempfile'

ARGV.each do |path|
    string_in = File.read(path)
    registry = TypeStore::IO::XMLImporter.import(string_in, registry: TypeStore::CXX::Registry.new)

    xml_in  = REXML::Document.new(string_in)
    xml_out = TypeStore::IO::XMLExporter.new.to_xml(registry)

    string_in, string_out = '', ''
    REXML::Formatters::Default.new.write(xml_in, string_in)
    REXML::Formatters::Default.new.write(xml_out, string_out)

    string_in = IO.popen("xmllint --format -", 'r+') do |io|
        io.write string_in
        io.close_write
        io.read
    end
    normal, aliases = string_in.split("\n").partition { |line| line =~ /<alias/ }
    string_in = (normal + aliases).join("\n")

    string_out = IO.popen("xmllint --format -", 'r+') do |io|
        io.write string_out
        io.close_write
        io.read
    end
    normal, aliases = string_out.split("\n").partition { |line| line =~ /<alias/ }
    string_out = (normal + aliases).join("\n")
    File.open(File.basename(path) + ".1", 'w') { |io| io.write(string_in) }
    File.open(File.basename(path) + ".2", 'w') { |io| io.write(string_out) }
end

