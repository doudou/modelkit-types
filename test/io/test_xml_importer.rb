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

            it "raises ImportError when finding an unknown tag" do
                assert_raises(ImportError) do
                    import_type '/test', '<typelib><unknown name="/bla" /></typelib>'
                end
            end

            it "only considers the CDATA tags contents when importing metadata" do
                test_t = import_type '/test', '<typelib><numeric name="/test" size="10">\n<metadata key="test">\n     <![CDATA[value]]></metadata></numeric></typelib>'
                assert_equal ['value'], test_t.metadata.get('test').to_a
            end
        end
    end
end


