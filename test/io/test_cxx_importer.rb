require 'modelkit/types/test'
require 'modelkit/types/io/cxx_importer'
require_relative './cxx_common_tests'
require_relative './cxx_gccxml_common'

module ModelKit::Types
    module IO
        describe CXXImporter do
            after do
                CXXImporter.loader = nil
                ENV.delete('MODELKIT_TYPES_CXX_LOADER')
            end

            it "returns the importer that matches the MODELKIT_TYPES_CXX_LOADER envvar" do
                ENV['MODELKIT_TYPES_CXX_LOADER'] = 'castxml'
                assert_equal CXX::CastXMLLoader, CXXImporter.loader
                ENV['MODELKIT_TYPES_CXX_LOADER'] = 'gccxml'
                assert_equal CXX::GCCXMLLoader, CXXImporter.loader
            end
            it "raises ArgumentError if the envvar does not match an known loader" do
                ENV['MODELKIT_TYPES_CXX_LOADER'] = 'does_not_exist'
                assert_raises(ArgumentError) do
                    CXXImporter.loader
                end
            end
            it "returns an explicitely set loader" do
                CXXImporter.loader = loader = flexmock
                assert_equal loader, CXXImporter.loader
            end
            it "returns the GCC-XML loader by default" do
                assert_equal CXX::CastXMLLoader, CXXImporter.loader
            end

            describe ".import" do
                attr_reader :cxx_path, :expected_registry
                before do
                    @cxx_path = Pathname.new(__dir__) + "cxx_import_tests" + "enums.hh"

                    @expected_registry = CXX::Registry.new
                    tlb = Registry.from_xml(cxx_path.sub_ext('.tlb').read)
                    expected_registry.merge(tlb)
                end
                it "loads a C++ file using the default loader and returns the generated registry" do
                    registry = CXXImporter.import(cxx_path.to_s)
                    assert expected_registry.same_types?(registry)
                end
                it "can be given a registry" do
                    registry = CXX::Registry.new
                    CXXImporter.import(cxx_path.to_s, registry: registry)
                    assert expected_registry.same_types?(registry)
                end
                it "can be given a loader" do
                    loader = flexmock
                    loader.should_receive(:import).once
                    CXXImporter.import(cxx_path.to_s, cxx_importer: loader)
                end
                it "passes extra options to the loader" do
                    registry = flexmock
                    loader = flexmock
                    loader.should_receive(:import).once.
                        with(cxx_path.to_s, registry: registry, extra: :options)
                    CXXImporter.import(cxx_path.to_s, registry: registry, cxx_importer: loader, extra: :options)
                end
            end

            describe "in castxml mode" do
                include CXXCommonTests

                before do
                    CXX::GCCXMLLoader.make_own_logger 'GCCXMLLoader', Logger::FATAL
                    if !find_in_path(CXX::GCCXMLLoader.castxml_binary_name)
                        skip("castxml not installed")
                    end
                    setup_loader 'castxml'
                end

                # libstdc++ in GCC 5 and above have strings of 32 bytes, before
                # of 8. This is detected as a failure in the tests
                def test_cxx_common_strings
                    native_sizes = ['/std/string', '/std/wstring', '/strings/S1', '/strings/S2']
                    super do |reg, xml|
                        xml.root.elements.to_a.each do |node|
                            if native_sizes.include?(node.attributes['name'])
                                node.attributes['size'] = reg.get(node.attributes['name']).size
                            end
                        end
                    end
                end

                def test_cxx_common_NamedVector
                    native_sizes = ['/std/string', '/std/wstring']
                    super do |reg, xml|
                        xml.root.elements.to_a.each do |node|
                            if native_sizes.include?(node.attributes['name'])
                                node.attributes['size'] = reg.get(node.attributes['name']).size
                            end
                        end
                    end
                end

                include CXX_GCCXML_Common
            end

            describe "in gccxml mode" do
                include CXXCommonTests

                before do
                    CXX::GCCXMLLoader.make_own_logger 'GCCXMLLoader', Logger::FATAL
                    if !find_in_path('gccxml')
                        skip("gccxml not installed")
                    end
                    setup_loader 'gccxml'
                end

                include CXX_GCCXML_Common
            end
        end
    end
end

