require 'modelkit/types/test'

module ModelKit::Types
    describe "#validate_typename" do
        it "accepts type names starting with an underscore" do
            ModelKit::Types.validate_typename "/standard/__1/StandardClass"
        end
    end
end
