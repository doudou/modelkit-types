require 'test_helper'
module ModelKit::Types
    describe NumericType do
        attr_reader :int_t
        before do
            @int_t = Registry.new.create_numeric '/int32', size: 4
        end

        it "allocates a buffer of the required size" do
            assert_equal 4, int_t.new.__buffer.size
        end

        it "does not validate the buffer in wrap!" do
            int_t.wrap!("\x0")
        end

        it "raises in wrap if trying to set it up with a buffer of the wrong size" do
            assert_raises(InvalidBuffer) do
                int_t.wrap("\x0")
            end
        end

        it "sets and gets the value" do
            value = int_t.new
            value.from_ruby(324553)
            assert_kind_of Buffer, value.__buffer
            assert_equal 324553, value.to_ruby
        end

        it "raises AbstractType if attempting to instanciate a numeric type without size" do
            type = NumericType.new_submodel(size: nil)
            assert_raises(AbstractType) do
                type.new
            end
        end

        it "raises AbstractType if attempting to instanciate a numeric type that does not have a pack code" do
            type = NumericType.new_submodel(size: 5)
            assert_raises(AbstractType) do
                type.new
            end
        end

        describe "#to_simple_value" do
            attr_reader :float_t, :int_t
            before do
                registry = Registry.new
                @float_t = registry.create_numeric '/float32', size: 4, integer: false
                @int_t   = registry.create_numeric '/int32', size: 4, integer: true
            end

            it "raises ArgumentError if the special_float_values argument is not one of the expected settings" do
                assert_raises(ArgumentError) do
                    float_t.new.to_simple_value(special_float_values: 'not ewxpected')
                end
            end

            describe "special_float_values: nil" do
                it "returns the plain value for integers" do
                    assert_equal 2314, int_t.from_buffer([2314].pack("L<")).to_simple_value
                end

                it "returns the plain value for normal floats" do
                    assert_in_delta 0.1, float_t.from_buffer([0.1].pack("F")).to_simple_value, 1e-6
                end

                it "returns the plain value for NaN" do
                    assert float_t.from_buffer([Float::NAN].pack("F")).to_simple_value.nan?
                end

                it "returns the plain value for Infinity" do
                    assert float_t.from_buffer([Float::INFINITY].pack("F")).to_simple_value.infinite?
                end
            end

            describe "special_float_values: :nil" do
                it "returns the plain value for integers" do
                    assert_equal(2314, int_t.from_buffer([2314].pack("L<")).
                                 to_simple_value(special_float_values: :nil))
                end

                it "returns the plain value for normal floats" do
                    assert_in_delta(0.1, float_t.from_buffer([0.1].pack("F")).
                                    to_simple_value(special_float_values: :nil), 1e-6)
                end

                it "returns nil for NaN" do
                    assert_nil float_t.from_buffer([Float::NAN].pack("F")).
                        to_simple_value(special_float_values: :nil)
                end

                it "returns nil for Infinity" do
                    assert_nil float_t.from_buffer([Float::INFINITY].pack("F")).
                        to_simple_value(special_float_values: :nil)
                    assert_nil float_t.from_buffer([-Float::INFINITY].pack("F")).
                        to_simple_value(special_float_values: :nil)
                end
            end

            describe "special_float_values: :string" do
                it "returns the plain value for integers" do
                    assert_equal(2314, int_t.from_buffer([2314].pack("L<")).
                                 to_simple_value(special_float_values: :string))
                end

                it "returns the plain value for normal floats" do
                    assert_in_delta(0.1, float_t.from_buffer([0.1].pack("F")).
                                    to_simple_value(special_float_values: :string), 1e-6)
                end

                it "returns the plain value for NaN" do
                    assert_equal('NaN', float_t.from_buffer([Float::NAN].pack("F")).
                        to_simple_value(special_float_values: :string))
                end

                it "returns the plain value for Infinity" do
                    assert_equal('Infinity', float_t.from_buffer([Float::INFINITY].pack("F")).
                        to_simple_value(special_float_values: :string))
                    assert_equal('-Infinity', float_t.from_buffer([-Float::INFINITY].pack("F")).
                        to_simple_value(special_float_values: :string))
                end
            end
        end
    end
end

