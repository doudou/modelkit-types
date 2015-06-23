require 'typestore/test'

module TypeStore
    module Models
        describe EnumType do
            attr_reader :enum_t
            before do
                @enum_t = TypeStore::EnumType.new_submodel(typename: 'Test')
            end

            describe "#add" do
                it "adds a new symbol/value pair to the enum" do
                    enum_t.add :TEST0, 10
                    enum_t.add :TEST1, 20
                    assert_equal Hash[TEST0: 10, TEST1: 20], enum_t.symbol_to_value
                    assert_equal Hash[10 => :TEST0, 20 => :TEST1], enum_t.value_to_symbol
                end
            end

            describe "#each" do
                it "enumerates the existing symbol/value pairs" do
                    enum_t.add :TEST0, 10
                    enum_t.add :TEST1, 20
                    assert_equal [[:TEST0, 10], [:TEST1, 20]], enum_t.each.to_a
                end
            end

            describe "#to_h" do
                it "should be able to describe the type" do
                    enum_t.add :TEST0, 10
                    enum_t.add :TEST1, 20
                    expected = Hash[class: 'EnumType',
                                    name: enum_t.name,
                                    values: [
                                        Hash[name: 'TEST0', value: 10],
                                        Hash[name: 'TEST1', value: 20]
                                    ]]
                    assert_equal expected, enum_t.to_h
                end
            end
            
            describe "#value_of" do
                before do
                    enum_t.add :TEST, 10
                end
                it "returns the value of a symbol" do
                    assert_equal 10, enum_t.value_of(:TEST)
                end
                it "raises ArgumentError if there are no symbols with this value" do
                    assert_raises(ArgumentError) { enum_t.value_of(:DOES_NOT_EXIST) }
                end
            end
            
            describe "#name_of" do
                before do
                    enum_t.add :TEST, 10
                end
                it "returns the value of a symbol" do
                    assert_equal :TEST, enum_t.name_of(10)
                end
                it "raises ArgumentError if there are no symbols with this value" do
                    assert_raises(ArgumentError) { enum_t.name_of(20) }
                end
            end
        end
    end
end

