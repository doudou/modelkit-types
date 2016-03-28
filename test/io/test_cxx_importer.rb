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
                    if !find_in_path('castxml')
                        skip("castxml not installed")
                    end
                    setup_loader 'castxml'
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

