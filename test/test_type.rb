require 'modelkit/types/test'
module ModelKit::Types
    describe Type do
        attr_reader :type
        before do
            @type = Type.new_submodel
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
    end
end

