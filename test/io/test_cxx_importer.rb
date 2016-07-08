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

            it "autodetects 'castxml' if it is available" do
                flexmock(TTY::Which).should_receive(:which).with('castxml').and_return('/usr/bin/castxml')
                flexmock(TTY::Which).should_receive(:exist?).with('/usr/bin/castxml').and_return(true)
                loader = CXXImporter.loader
                assert_equal CXX::CastXMLLoader, loader
                assert_equal '/usr/bin/castxml', loader.binary_path
            end

            it "autodetects 'gccxml' if castxml is not available and gccxml is" do
                flexmock(TTY::Which).should_receive(:which).with('castxml').and_return(nil)
                flexmock(TTY::Which).should_receive(:which).with('gccxml').and_return('/path/to/gccxml')
                flexmock(TTY::Which).should_receive(:exist?).with('/path/to/gccxml').and_return(true)
                loader = CXXImporter.loader
                assert_equal CXX::GCCXMLLoader, loader
                assert_equal '/path/to/gccxml', loader.binary_path
            end

            it "returns the importer that matches the MODELKIT_TYPES_CXX_LOADER envvar" do
                ENV['MODELKIT_TYPES_CXX_LOADER'] = 'castxml'
                flexmock(TTY::Which).should_receive(:which).with('castxml').and_return('/path/to/castxml')
                flexmock(TTY::Which).should_receive(:exist?).with('/path/to/castxml').and_return(true)
                loader = CXXImporter.loader
                assert_equal CXX::CastXMLLoader, loader
                assert_equal '/path/to/castxml', loader.binary_path
            end
            it "raises ImporterNotFound if the binary inferred by MODELKIT_TYPES_CXX_LOADER cannot be found" do
                ENV['MODELKIT_TYPES_CXX_LOADER'] = 'castxml'
                flexmock(TTY::Which).should_receive(:which).with('castxml').and_return(nil)
                assert_raises(CXXImporter::ImporterNotFound) do
                    CXXImporter.loader
                end
            end
            it "selects the binary explicitely selected by MODELKIT_TYPES_CXX_LOADER" do
                ENV['MODELKIT_TYPES_CXX_LOADER'] = 'castxml:/path/to/castxml'
                flexmock(TTY::Which).should_receive(:exist?).with('/path/to/castxml').and_return(true)
                loader = CXXImporter.loader
                assert_equal CXX::CastXMLLoader, loader
                assert_equal '/path/to/castxml', loader.binary_path
            end

            it "raises ImporterNotFound if the binary explicitely specified by MODELKIT_TYPES_CXX_LOADER cannot be found" do
                ENV['MODELKIT_TYPES_CXX_LOADER'] = 'castxml:/path/to/castxml'
                flexmock(TTY::Which).should_receive(:exist?).with('/path/to/castxml').and_return(false)
                assert_raises(CXXImporter::ImporterNotFound) do
                    CXXImporter.loader
                end
            end
            it "raises ImporterNotFound MODELKIT_TYPES_CXX_LOADER does not match an known loader" do
                ENV['MODELKIT_TYPES_CXX_LOADER'] = 'does_not_exist'
                assert_raises(CXXImporter::ImporterNotFound) do
                    CXXImporter.loader
                end
            end
            it "selects automatically the loader type if it matches the binary path" do
                ENV['MODELKIT_TYPES_CXX_LOADER'] = '/path/to/gccxml'
                flexmock(TTY::Which).should_receive(:exist?).with('/path/to/gccxml').and_return(true)
                loader = CXXImporter.loader
                assert_equal CXX::GCCXMLLoader, loader
                assert_equal '/path/to/gccxml', loader.binary_path
            end

            it "returns an explicitely set loader" do
                CXXImporter.loader = loader = flexmock
                assert_equal loader, CXXImporter.loader
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
                    CXX::GCCXMLLoader.make_own_logger 'CastXMLLoader', Logger::FATAL
                    if !TTY::Which.exist?('castxml')
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

