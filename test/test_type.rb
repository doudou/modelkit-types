require 'modelkit/types/test'
module ModelKit::Types
    describe Type do
        attr_reader :type, :int32_t, :array_t
        before do
            @type = Type.new_submodel
            @int32_t = NumericType.new_submodel(size: 4, integer: true, unsigned: false)
            @array_t = ArrayType.new_submodel(deference: int32_t, length: 10)
        end

        def make_int32(v)
            value = int32_t.new
            value.from_ruby(v)
            value
        end

        describe ".from_buffer" do
            it "calls wrap with a copy of the buffer" do
                buffer = "    "
                flexmock(type).should_receive(:wrap).once.
                    with(->(b) { b.to_str == buffer && b.backing_buffer.object_id != buffer.object_id }).
                    and_return(ret = flexmock)
                assert_equal ret, type.from_buffer(buffer)
            end
        end

        describe ".from_buffer!" do
            it "calls wrap! with a copy of the buffer" do
                buffer = "    "
                flexmock(type).should_receive(:wrap!).once.
                    with(->(b) { b.to_str == buffer && b.backing_buffer.object_id != buffer.object_id }).
                    and_return(ret = flexmock)
                assert_equal ret, type.from_buffer!(buffer)
            end
        end

        describe ".new" do
            it "initializes the type with a buffer of zeroes" do
                type_t = Type.new_submodel(size: 10)
                assert_equal ("\x0" * 10), type_t.new.__buffer.to_str
            end
        end

        describe "#dup" do
            attr_reader :type, :value
            before do
                @type = Type.new_submodel(size: 5)
                @value = type.from_buffer!("01234")
            end
            it "creates a new value with a copy of the underlying buffer" do
                dup = value.dup
                refute_same value.__buffer.backing_buffer, dup.__buffer.backing_buffer
                assert dup.__buffer.whole?
            end
            it "uses #to_byte_array to get the underlying buffer" do
                # This is important, as to_byte_array is the hook point for
                # variable-size types to marshal their updates
                flexmock(value).should_receive(:to_byte_array).and_return("abcde").once
                dup = value.dup
                assert_equal "abcde", dup.__buffer.backing_buffer
            end
        end

        describe "#copy_to" do
            it "copies the buffer content" do
                type = Type.new_submodel(size: 2)
                buffer = Buffer.new(raw = "012345".dup, 2, 2)
                value = type.wrap!(buffer)
                target_buffer = Buffer.new(target_raw = "abcdef".dup, 2, 2)
                target = type.wrap(target_buffer)
                value.copy_to(target)
                assert_equal "ab23ef", target_raw
            end
            it "raises on incompatible types" do
                type = Type.new_submodel(size: 2)
                other_t = Type.new_submodel(size: 4)

                assert_raises(InvalidCopy) do
                    type.new.copy_to(other_t.new)
                end
            end
        end

        describe "#cast" do
            it "creates a new value with the backing buffer narrowed to the udnerlying size" do
                array = array_t.new
                array.set(0, make_int32(10))
                casted = array.cast(int32_t)
                assert_kind_of int32_t, casted
                assert_equal 10, casted.to_ruby
                assert_equal 4, casted.__buffer.size
            end
            it "raises InvalidCast if the cast is not possible" do
                array = array_t.new
                array.set(0, make_int32(10))
                assert_raises(InvalidCast) do
                    array.cast(type)
                end
            end
        end
    end
end

