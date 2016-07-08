require 'test_helper'

module ModelKit::Types
    module IO
        describe XMLExporter do
            attr_reader :exporter
            before do
                @exporter = XMLExporter.new
            end

            it "can export and reimport all TLBs from the C++ import tests" do
                Pathname.glob(Pathname.new(__dir__) + "cxx_import_tests" + "*.tlb") do |tlb_path|
                    registry = Registry.from_xml(tlb_path.read)
                    xml = registry.to_xml
                    imported_registry = Registry.from_xml(xml)
                    assert(registry.same_types?(imported_registry), "#{tlb_path}")
                end
            end

            it "can import/export a plain type" do
                registry = Registry.new
                type = registry.create_type '/Test'
                imported_registry = Registry.from_xml(type.to_xml)
                assert registry.same_types?(imported_registry)
            end

            it "can import/export a null type" do
                registry = Registry.new
                type = registry.create_type '/Test', null: true
                imported_registry = Registry.from_xml(type.to_xml)
                assert registry.same_types?(imported_registry)
            end

            describe ".export" do
                attr_reader :registry
                before do
                    @registry = Registry.new
                end

                it "exports the registry to string" do
                    xml = XMLExporter.export(registry)
                    assert registry.same_types?(Registry.from_xml(xml))
                end

                it "allows to specify an IO as output" do
                    io = StringIO.new
                    XMLExporter.export(registry, to: io)
                    assert registry.same_types?(Registry.from_xml(io.string))
                end
            end

            describe "#export" do
                attr_reader :registry
                before do
                    @registry = Registry.new
                end

                it "exports the given registry to XML marshalled as string" do
                    xml = exporter.export(registry)
                    assert registry.same_types?(Registry.from_xml(xml))
                end

                it "allows to specify an IO as output" do
                    io = StringIO.new
                    exporter.export(registry, to: io)
                    assert registry.same_types?(Registry.from_xml(io.string))
                end
            end
        end
    end
end
