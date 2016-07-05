require 'modelkit/types/test'

module ModelKit::Types
    describe EnumType do
        attr_reader :enum_t
        before do
            registry = Registry.new
            @enum_t = registry.create_enum '/Test', size: 4 do |e|
                e.add :TEST0, 10
                e.add :TEST1, 20
            end
        end

        describe "#from_ruby" do
            it "initializes with the value that matches the given symbol" do
                enum = enum_t.new
                enum.from_ruby(:TEST0)
                assert_equal [10].pack("l<"), enum.__buffer.to_str
            end
            it "initializes with the value that matches the given string" do
                enum = enum_t.new
                enum.from_ruby('TEST0')
                assert_equal [10].pack("l<"), enum.__buffer.to_str
            end
            it "raises InvalidEnumValue if the given symbol is not part of the enumeration" do
                enum = enum_t.new
                assert_raises(InvalidEnumValue) do
                    enum.from_ruby('does_not_exist')
                end
            end
        end

        describe "#to_ruby" do
            it "returns the symbol that matches the embedded value" do
                enum = enum_t.wrap([10].pack("l<"))
                assert_equal :TEST0, enum.to_ruby
            end
            it "raises InvalidEnumValue if the embedded value does not have a matching symbol" do
                enum = enum_t.wrap([15].pack("l<"))
                assert_raises(InvalidEnumValue) do
                    enum.to_ruby
                end
            end
        end

        describe "#to_simple_value" do
            it "returns the value's string representation" do
                enum = enum_t.wrap([10].pack("l<"))
                assert_equal 'TEST0', enum.to_simple_value
            end
        end
    end
end

