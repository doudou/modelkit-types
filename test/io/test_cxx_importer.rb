require 'modelkit/types/test'
require 'modelkit/types/io/cxx_importer'

module ModelKit::Types
    module IO
        describe CXXImporter do
            def data_dir; Pathname.new(__FILE__).dirname.expand_path + "cxx" end

            it "imports fundamental types with standardized names" do
                registry = CXXImporter.import(data_dir + "fundamentals.hpp")
                int_t = registry.get '/int64_t'
                assert_equal '/int64_t', int_t.name

                expected = NumericType.new_submodel(typename: '/int64_t', integer: true, size: 8)
                assert_equal expected, int_t
            end
            
            it "imports simple structures" do
                registry = CXXImporter.import(data_dir + "compound.hpp")
                bool_t = registry.get '/Bool'
                assert_equal registry.get('/bool'), bool_t.get('field').type
            end

            it "handles stdint.h properly" do
                registry = CXXImporter.import(data_dir + "stdint_import.hpp")
                int_t = registry.get '/int32_t'
                assert_equal '/int32_t', int_t.name
            end
        end
    end
end
