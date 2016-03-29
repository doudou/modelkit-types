require 'modelkit/types/test'
require 'modelkit/types/io/cxx_importer'
require_relative './cxx_common_tests'
require_relative './cxx_gccxml_common'

module ModelKit::Types
    module IO
        describe CXXImporter do
            describe "in castxml mode" do
                include CXXCommonTests

                before do
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

