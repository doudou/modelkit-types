require 'modelkit/types/test'

module ModelKit::Types
    describe ArrayType do
        attr_reader :int32_t
        before do
            @int32_t = NumericType.new_submodel(size: 4)
        end

        describe "#__offset_and_size_of" do
            attr_reader :array
            before do
                array_t = ArrayType.new_submodel(deference: int32_t, length: 4)
                @array = array_t.from_buffer([1, 2, 3, 4].pack("l<*"))
            end

            it "returns the offset of the n-th element" do
                assert_equal [0, 4], array.__offset_and_size_of(0)
                assert_equal [12, 4], array.__offset_and_size_of(3)
            end
        end

        describe "#get" do
            attr_reader :array, :array_t

            before do
                @array_t = ArrayType.new_submodel(deference: int32_t, length: 4)
                @array = array_t.from_buffer([10, 20, 30, 40].pack("l<*"))
            end

            it "returns the n-th element" do
                assert_equal 40, array.get(3).to_simple_value
            end
            it "caches the element" do
                assert_same array.get(3), array.get(3)
            end
            it "creates elements that point to the same backing buffer" do
                array.get(3).from_ruby(400)
                assert_equal [10, 20, 30, 400], array.__buffer.unpack("l<*")
            end
        end

        describe "#set" do
            attr_reader :array, :array_t

            before do
                array_t = ArrayType.new_submodel(deference: int32_t, length: 4)
                @array = array_t.from_buffer([10, 20, 30, 40].pack("l<*"))
            end

            it "sets the value at the given index" do
                raw = [10].pack("l<")
                ten = int32_t.wrap(raw)
                array.set(3, ten)
                assert_equal raw, array.get(3).__buffer.to_str
            end
            it "validates the compatibility of the source value" do
                int64_t = NumericType.new_submodel(size: 8)
                ten = int64_t.wrap([10].pack("Q<"))
                assert_raises(IncompatibleTypes) do
                    array.set(3, ten)
                end
            end
        end

        describe "#[]=" do
            attr_reader :array

            before do
                array_t = ArrayType.new_submodel(deference: int32_t, length: 4)
                @array = array_t.from_buffer([10, 20, 30, 40].pack("l<*"))
            end
            it "is an alias for set" do
                flexmock(array).should_receive(:set).with(index = flexmock, value = flexmock).once
                array[index] = value
            end
        end

        describe "#set!" do
            attr_reader :array, :array_t

            before do
                @array_t = ArrayType.new_submodel(deference: int32_t, length: 4)
                @array = array_t.from_buffer([10, 20, 30, 40].pack("l<*"))
            end

            it "sets the value at the given index" do
                raw = [10].pack("l<")
                ten = int32_t.wrap(raw)
                array.set!(3, ten)
                assert_equal raw, array.get(3).__buffer.to_str
            end
            it "does not validate the compatibility of the source value" do
                float32_t = NumericType.new_submodel(size: 4, integer: false)
                ten = float32_t.wrap([10].pack("l<"))
                array.set!(3, ten)
                assert_equal 10, array.get(3).to_simple_value
            end
            it "does validate that the source and target values have the same size" do
                int64_t = NumericType.new_submodel(size: 8)
                ten = int64_t.wrap([10].pack("Q<"))
                assert_raises(IncompatibleTypes) do
                    array.set(3, ten)
                end
            end
        end

        describe "#[]" do
            attr_reader :array
            before do
                array_t = ArrayType.new_submodel(deference: int32_t, length: 4)
                @array = array_t.from_buffer([10, 20, 30, 40].pack("l<*"))
            end

            it "returns the n-th element" do
                assert_equal 40, array[3].to_simple_value
            end
            it "caches elements" do
                array_3 = array[3]
                assert_same array_3, array.get(3)
            end
            it "returns already cached elements in index form" do
                array_3 = array.get(3)
                assert_same array_3, array[3]
            end
            it "returns the range starting at offset and for the given size" do
                assert_equal [20, 30, 40], array[1, 3].map(&:to_simple_value)
            end
            it "caches elements" do
                expected = array[1, 3]
                actual   = (1..3).map { |i| array.get(i) }
                expected.zip(actual) do |a, b|
                    assert_same a, b
                end
            end
            it "returns already cached elements in offset,size form" do
                expected = (1..3).map { |i| array.get(i) }
                actual   = array[1, 3]
                expected.zip(actual) do |a, b|
                    assert_same a, b
                end
            end
            it "returns the given range" do
                assert_equal [20, 30], array[1..2].map(&:to_simple_value)
            end
            it "caches elements" do
                expected = array[1..3]
                actual   = (1..3).map { |i| array.get(i) }
                expected.zip(actual) do |a, b|
                    assert_same a, b
                end
            end
            it "returns already cached elements in offset,size form" do
                expected = (1..3).map { |i| array.get(i) }
                actual   = array[1..3]
                expected.zip(actual) do |a, b|
                    assert_same a, b
                end
            end
        end

        describe "#each" do
            attr_reader :array
            before do
                array_t = ArrayType.new_submodel(deference: int32_t, length: 4)
                @array = array_t.from_buffer([10, 20, 30, 40].pack("l<*"))
            end
            it "enumerates the elements" do
                assert_equal [10, 20, 30, 40], array.map(&:to_simple_value)
            end
            it "reuses cached elements" do
                array_1 = array.get(1)
                assert_same array_1, array.to_a[1]
            end
            it "leaves a coherent internal state if interrupted" do
                array.each_with_index { |i| break if i == 3 }
                assert_equal [10, 20, 30, 40], array.map(&:to_simple_value)
            end
            it "caches the elements it enumerates" do
                array_1 = array.to_a[1]
                assert_same array_1, array.get(1)
            end
        end

        describe "#to_simple_value" do
            attr_reader :backing_buffer, :array
            before do
                array_t = ArrayType.new_submodel(deference: int32_t, length: 4)
                @backing_buffer = [10, 20, 30, 40].pack("l<*")
                @array = array_t.from_buffer(backing_buffer)
            end
            describe "simple array packing" do
                it "packs the array in a single string" do
                    result = array.to_simple_value
                    assert_equal Hash[pack_code: "l<",
                                      size: 4,
                                      data: Base64.strict_encode64(backing_buffer)], result

                end
            end
            describe "without simple array packing" do
                it "returns the array element-by-element" do
                    result = array.to_simple_value(pack_simple_arrays: false)
                    assert_equal [10, 20, 30, 40], result

                end
            end
        end

        describe "#pretty_print" do
            attr_reader :backing_buffer, :array
            before do
                array_t = ArrayType.new_submodel(deference: int32_t, length: 4)
                @backing_buffer = [10, 20, 30, 40].pack("l<*")
                @array = array_t.from_buffer(backing_buffer)
            end

            it "pretty prints" do
                result = PP.pp(array, "")
                assert_equal <<-EOTEXT, result
[ [0] = 10, [1] = 20, [2] = 30, [3] = 40 ]
                EOTEXT

                result = PP.pp(array, "", 20)
                assert_equal <<-EOTEXT, result
[
  [0] = 10,
  [1] = 20,
  [2] = 30,
  [3] = 40
]
                EOTEXT
            end
        end
    end
end

