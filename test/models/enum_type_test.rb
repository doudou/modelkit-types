require 'test_helper'

module ModelKit::Types
    module Models
        describe EnumType do
            attr_reader :enum_t
            before do
                @enum_t = ModelKit::Types::EnumType.new_submodel(typename: 'Test')
            end

            it "has a name" do
                assert_equal "ModelKit::Types::EnumType", ModelKit::Types::EnumType.name
            end
            it "has a metadata object" do
                assert ModelKit::Types::EnumType.metadata
            end
            it "is of fixed buffer size" do
                assert ModelKit::Types::EnumType.new_submodel.fixed_buffer_size?
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

            describe "#merge" do
                it "merges the symbol_to_value and value_to_symbol mappings" do
                    enum_t.add :TEST, 10
                    enum_t.add :TEST1, 20
                    other_t = ModelKit::Types::EnumType.new_submodel(typename: 'Test')
                    other_t.add :TEST, 10
                    other_t.add :TEST2, 20
                    assert_equal Hash[TEST: 10, TEST1: 20, TEST2: 20],
                        other_t.merge(enum_t).symbol_to_value
                end
            end
            describe "#validate_merge" do
                it "passes if the two enums do not have colliding symbol-to-value mappings" do
                    enum_t.add :TEST, 10
                    enum_t.add :TEST1, 20
                    other_t = ModelKit::Types::EnumType.new_submodel(typename: 'Test')
                    other_t.add :TEST, 10
                    other_t.add :TEST2, 20
                    other_t.validate_merge(enum_t)
                end
                it "raises if the two enums have different values for the same symbol" do
                    enum_t.add :TEST, 10
                    other_t = ModelKit::Types::EnumType.new_submodel(typename: 'Test')
                    other_t.add :TEST, 20
                    assert_raises(MismatchingEnumSymbolsError) { enum_t.validate_merge(other_t) }
                end
            end
            describe "#copy_to" do
                it "copies the symbol-to-value mappings to the new type" do
                    registry = Registry.new
                    enum_t = registry.create_enum '/Test' do |e|
                        e.add :TEST, 10
                        e.add :TEST1, 20
                    end
                    target_registry = Registry.new
                    target_registry.merge(registry)
                    target_t = target_registry.get('/Test')
                    assert_equal Hash[TEST: 10, TEST1: 20], target_t.symbol_to_value
                end
            end
            describe "#pretty_print" do
                it "pretty-prints itself without values if verbose is false" do
                    enum_t.add :TEST, 10
                    enum_t.add :TEST1, 20
                    result = PP.singleline_pp(enum_t, "")
                    assert_equal "Test { TEST, TEST1 }", result
                end
                it "does proper multi-line formatting" do
                    enum_t.add :TEST, 10
                    enum_t.add :TEST1, 20
                    result = PP.pp(enum_t, "", 10)
                    assert_equal <<-EOTEXT, result
Test {
  TEST,
  TEST1
}
                    EOTEXT
                end
            end
        end
    end
end

