require 'typestore/test'

module TypeStore
    module Models
        describe NumericType do
            describe "#new_submodel" do
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

            describe "#to_h" do
                attr_reader :int_t, :uint_t, :float_t
                before do
                    @int_t = TypeStore::NumericType.new_submodel(
                        size: 4, integer: true, unsigned: false)
                    @uint_t = TypeStore::NumericType.new_submodel(
                        size: 4, integer: true, unsigned: true)
                    @float_t = TypeStore::NumericType.new_submodel(
                        size: 4, integer: false)
                end
                it "should report a class of 'NumericType'" do
                    assert_equal 'NumericType', int_t.to_h[:class]
                end
                it "should always have a size field" do
                    info = int_t.to_h(layout_info: false)
                    assert_equal 4, info[:size]
                end
                it "should add the unsigned flag to integer type descriptions" do
                    assert_equal false, int_t.to_h[:unsigned]
                    assert_equal true, uint_t.to_h[:unsigned]
                end
                it "should not add the unsigned flag to float type descriptions" do
                    assert !float_t.to_h.has_key?(:unsigned)
                end
                it "should convert an integer type description" do
                    expected = Hash[name: int_t.name,
                                    class: 'NumericType',
                                    size: 4,
                                    integer: true,
                                    unsigned: false]
                    assert_equal expected, int_t.to_h
                end
                it "should convert a float type description" do
                    expected = Hash[name: float_t.name,
                                    class: 'NumericType',
                                    size: 4,
                                    integer: false]
                    assert_equal expected, float_t.to_h
                end
            end

            describe "#pack_code" do
                it "can return the pack code of a float" do
                    float_t = TypeStore::NumericType.new_submodel(
                        size: 8, integer: false)
                    if TypeStore.big_endian?
                        assert_equal "G", float_t.pack_code
                    else
                        assert_equal "E", float_t.pack_code
                    end
                end
                it "can return the pack code of an integer" do
                    int_t = TypeStore::NumericType.new_submodel(
                        size: 4, integer: true, unsigned: false)
                    if TypeStore.big_endian?
                        assert_equal "l>", int_t.pack_code
                    else
                        assert_equal "l<", int_t.pack_code
                    end
                end
            end
        end
    end
end

