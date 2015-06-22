require 'typestore/test'

module TypeStore
    module Models
        describe NumericType do
            it "stores the name property" do
                float_t = TypeStore::NumericType.new_submodel(typename: '/Test')
                assert_equal '/Test', float_t.name
            end
            it "stores the size property" do
                float_t = TypeStore::NumericType.new_submodel(size: 10)
                assert_equal 10, float_t.size
            end
            it "stores the integer property" do
                numeric_t = TypeStore::NumericType.new_submodel(integer: true)
                assert numeric_t.integer?
                numeric_t = TypeStore::NumericType.new_submodel(integer: false)
                assert !numeric_t.integer?
            end
            it "stores the unsigned property" do
                numeric_t = TypeStore::NumericType.new_submodel(unsigned: true)
                assert numeric_t.unsigned?
                numeric_t = TypeStore::NumericType.new_submodel(unsigned: false)
                assert !numeric_t.unsigned?
            end
        end
    end
end

