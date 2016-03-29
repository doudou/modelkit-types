require 'modelkit/types/test'

module ModelKit::Types
    module IO
        describe XMLImporter do
            attr_reader :loader

            before do
                @loader = XMLImporter.new
            end

            def import_type(typename, xml)
                registry = Registry.new
                XMLImporter.new.from_xml(REXML::Document.new(xml), registry: registry)
                registry.get(typename)
            end

            it "imports opaque tags as types with opaque? set" do
                test_t = import_type '/test', '<typelib><opaque name="/test" /></typelib>'
                assert test_t.opaque?
            end

            it "imports null tags as types with opaque? set" do
                test_t = import_type '/test', '<typelib><null name="/test" /></typelib>'
                assert test_t.null?
            end
        end
    end
end


