require 'test_helper'
require 'modelkit/types/cxx'
require 'modelkit/types/cxx/gccxml_loader'

module ModelKit::Types
    module CXX
        # NOTE: there are no unit-level tests, but extensive functional tests in
        # test/io/test_cxx_importer
        describe GCCXMLInfo do
            describe "#parse" do
                subject do
                    GCCXMLInfo.new([])
                end

                it "raises ImportError if the XML stream does not start with the GCC_XML tag" do
                    assert_raises(ImportError) do
                        subject.parse("<TEST>\n</TEST>")
                    end
                end
            end
        end
    end
end

