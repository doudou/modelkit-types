require 'test_helper'
require 'modelkit/types/cxx'

module ModelKit::Types
    describe CXX do
        describe ".collect_template_arguments" do
            it "returns a single entry for a non-template stream" do
                assert_equal [['a', 'b']], CXX.collect_template_arguments(['a', 'b'])
            end
        end
    end
end
