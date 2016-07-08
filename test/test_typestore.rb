require 'modelkit/types/test'

describe ModelKit::Types do
    describe ".split_typename" do
        it "returns a single-element array for the root namespace" do
            assert_equal ["/"], ModelKit::Types.split_typename("/")
        end
    end
    describe ".typename_parts" do
        it "returns an empty array for the root namespace" do
            assert_equal [], ModelKit::Types.typename_parts('/')
        end

        it "handles simple cases" do
            assert_equal %w{NS2 NS3 Test}, ModelKit::Types.typename_parts("/NS2/NS3/Test")
        end
        it "handles template patterns as namespaces" do
            assert_equal %w{wrappers Matrix</double,3,1> Scalar},
                ModelKit::Types.typename_parts("/wrappers/Matrix</double,3,1>/Scalar")
        end
        it "handles template recursive templates as namespaces" do
            assert_equal %w{wrappers Matrix</double,3,1> Gaussian</double,3> Scalar},
                ModelKit::Types.typename_parts("/wrappers/Matrix</double,3,1>/Gaussian</double,3>/Scalar")
        end
        it "handles recursive templates as type basename" do
            assert_equal %w{std vector</wrappers/Matrix</double,3,1>>},
                ModelKit::Types.typename_parts("/std/vector</wrappers/Matrix</double,3,1>>")
        end

        describe "changing the namespace separator" do
            it "handles simple cases" do
                assert_equal %w{NS2 NS3 Test}, ModelKit::Types.typename_parts("/NS2/NS3/Test", separator: '::')
            end
            it "handles template patterns as namespaces" do
                assert_equal %w{wrappers Matrix<::double,3,1> Scalar},
                    ModelKit::Types.typename_parts("/wrappers/Matrix</double,3,1>/Scalar", separator: '::')
            end
            it "handles template recursive templates as namespaces" do
                assert_equal %w{wrappers Matrix<::double,3,1> Gaussian<::double,3> Scalar},
                    ModelKit::Types.typename_parts("/wrappers/Matrix</double,3,1>/Gaussian</double,3>/Scalar", separator: '::')
            end
            it "handles recursive templates as type basename" do
                assert_equal %w{std vector<::wrappers::Matrix<::double,3,1>>},
                    ModelKit::Types.typename_parts("/std/vector</wrappers/Matrix</double,3,1>>", separator: '::')
            end
        end
    end

    describe ".namespace" do
        it "handles simple cases" do
            assert_equal "/NS2/NS3/", ModelKit::Types.namespace("/NS2/NS3/Test")
        end
        it "handles template patterns as namespaces" do
            assert_equal"/wrappers/Matrix</double,3,1>/", ModelKit::Types.namespace("/wrappers/Matrix</double,3,1>/Scalar")
        end
        it "handles template recursive templates as namespaces" do
            assert_equal "/wrappers/Matrix</double,3,1>/Gaussian</double,3>/",
                ModelKit::Types.namespace("/wrappers/Matrix</double,3,1>/Gaussian</double,3>/Scalar")
        end
        it "handles recursive templates as type basename" do
            assert_equal "/std/", ModelKit::Types.namespace("/std/vector</wrappers/Matrix</double,3,1>>")
        end

        it "returns the separator for root types" do
            assert_equal '/', ModelKit::Types.namespace('/Test')
        end

        it "returns an empty namespace for root types if remove_leading is true" do
            assert_equal '', ModelKit::Types.namespace('/Test', remove_leading: true)
        end

        it "returns the namespace without the leading separator if remove_leading is true" do
            assert_equal "std/", ModelKit::Types.namespace("/std/vector</wrappers/Matrix</double,3,1>>", remove_leading: true)
        end

        describe "changing the namespace separator" do
            it "handles simple cases" do
                assert_equal "::NS2::NS3::", ModelKit::Types.namespace("/NS2/NS3/Test", separator: '::')
            end
            it "handles template patterns as namespaces" do
                assert_equal"::wrappers::Matrix<::double,3,1>::",
                    ModelKit::Types.namespace("/wrappers/Matrix</double,3,1>/Scalar", separator: '::')
            end
            it "handles template recursive templates as namespaces" do
                assert_equal "::wrappers::Matrix<::double,3,1>::Gaussian<::double,3>::",
                    ModelKit::Types.namespace("/wrappers/Matrix</double,3,1>/Gaussian</double,3>/Scalar", separator: '::')
            end
            it "handles recursive templates as type basename" do
                assert_equal "::std::", ModelKit::Types.namespace("/std/vector</wrappers/Matrix</double,3,1>>", separator: '::')
            end
        end
    end

    describe ".basename" do
        it "handles simple cases" do
            assert_equal "Test", ModelKit::Types.basename("/NS2/NS3/Test")
        end
        it "handles template patterns as basenames" do
            assert_equal "Scalar", ModelKit::Types.basename("/wrappers/Matrix</double,3,1>/Scalar")
        end
        it "handles template recursive templates as basenames" do
            assert_equal "Scalar",
                ModelKit::Types.basename("/wrappers/Matrix</double,3,1>/Gaussian</double,3>/Scalar")
        end
        it "handles recursive templates as type basename" do
            assert_equal "vector</wrappers/Matrix</double,3,1>>",
                ModelKit::Types.basename("/std/vector</wrappers/Matrix</double,3,1>>")
        end
        it "handles recursive templates as type basename with namespace change" do
            assert_equal "vector<::wrappers::Matrix<::double,3,1>>",
                ModelKit::Types.basename("/std/vector</wrappers/Matrix</double,3,1>>", separator: '::')
        end
        it "handles root types" do
            assert_equal 'Test', ModelKit::Types.basename('/Test')
        end
    end

    describe ".validate_typename" do
        it "raises TypeError if the argument is not a string" do
            assert_raises(TypeError) { ModelKit::Types.validate_typename(nil) }
        end
        it "raises if alphabetic characters are found as array subscripts" do
            assert_raises(ModelKit::Types::InvalidTypeNameError) { ModelKit::Types.validate_typename("/int[e]") }
        end
        it "raises if negative numbers are found as array subscripts" do
            assert_raises(ModelKit::Types::InvalidTypeNameError) { ModelKit::Types.validate_typename("/int[-10]") }
        end
        it "raises on known cases" do
            ModelKit::Types.validate_typename "/std/string</double>"
            ModelKit::Types.validate_typename "/std/string</double>"
            ModelKit::Types.validate_typename "/std/string</double,9,/std/string>"
            ModelKit::Types.validate_typename "/std/string<3>"
            ModelKit::Types.validate_typename "/double[3]"
            ModelKit::Types.validate_typename "/std/string</double[3]>"
            ModelKit::Types.validate_typename "/wrappers/Matrix</double,3,1>/Scalar"
            ModelKit::Types.validate_typename "/std/vector</wrappers/Matrix</double,3,1>>"
            ModelKit::Types.validate_typename "/std/vector</wrappers/Matrix</double,3,1>>[4]"
            ModelKit::Types.validate_typename "/std/map</std/string,/trigger/behaviour/Description,/std/less</std/string>,/std/allocator</std/pair</const std/basic_string</char,/std/char_traits</char>,/std/allocator</char>>,/trigger/behaviour/Description>>>"
        end
        it "raises on known cases" do
            assert_raises(ModelKit::Types::InvalidTypeNameError) { ModelKit::Types.validate_typename("std::string") }
            assert_raises(ModelKit::Types::InvalidTypeNameError) { ModelKit::Types.validate_typename("std::string") }
            assert_raises(ModelKit::Types::InvalidTypeNameError) { ModelKit::Types.validate_typename("/std/string<double>") }
            assert_raises(ModelKit::Types::InvalidTypeNameError) { ModelKit::Types.validate_typename("std/string<double>") }
            assert_raises(ModelKit::Types::InvalidTypeNameError) { ModelKit::Types.validate_typename("std/string</double>") }
            assert_raises(ModelKit::Types::InvalidTypeNameError) { ModelKit::Types.validate_typename("s") }
            assert_raises(ModelKit::Types::InvalidTypeNameError) { ModelKit::Types.validate_typename(":blabla") }
        end
        it "accepts type names starting with an underscore" do
            ModelKit::Types.validate_typename "/standard/__1/StandardClass"
        end
        it "accepts positive integers as first argument in templates" do
            ModelKit::Types.validate_typename "/Test<2>"
        end
        it "accepts negative integers as first argument in templates" do
            ModelKit::Types.validate_typename "/Test<-2>"
        end
        it "accepts positive integers as followup argument in templates" do
            ModelKit::Types.validate_typename "/Test</double,2>"
        end
        it "accepts negative integers as followup argument in templates" do
            ModelKit::Types.validate_typename "/Test</double,-2>"
        end
        it "accepts nested types with a template in the middle" do
            ModelKit::Types.validate_typename "/ns/Context</int>/Parameter"
        end
        it "raises InvalidTypeNameError if finding a closing template marker without an opening marker" do
            assert_raises(ModelKit::Types::InvalidTypeNameError) do
                ModelKit::Types.validate_typename "/std/Parameter</int>>"
            end
        end
        it "raises InvalidTypeNameError if finding an opening template marker unbalanced by a closing marker" do
            assert_raises(ModelKit::Types::InvalidTypeNameError) do
                ModelKit::Types.validate_typename "/std/Parameter</int"
            end
        end
        it "raises InvalidTypeNameError if finding a < followed by an unexpected character" do
            assert_raises(ModelKit::Types::InvalidTypeNameError) do
                ModelKit::Types.validate_typename "/std/Parameter<int>"
            end
        end
        it "raises InvalidTypeNameError if finding a / followed by an unexpected character" do
            assert_raises(ModelKit::Types::InvalidTypeNameError) do
                ModelKit::Types.validate_typename "/std/Parameter/</int>"
            end
        end
        it "raises InvalidTypeNameError if finding a , followed by an unexpected character" do
            assert_raises(ModelKit::Types::InvalidTypeNameError) do
                ModelKit::Types.validate_typename "/std/Parameter</int,i>"
            end
        end
        it "raises InvalidTypeNameError if finding a > followed by an unexpected character" do
            assert_raises(ModelKit::Types::InvalidTypeNameError) do
                ModelKit::Types.validate_typename "/std/Parameter</int>a"
            end
        end
    end

    describe ".parse_template" do
        it "handles typenames without template markers" do
            assert_equal ["base",[]], ModelKit::Types.parse_template("base")
        end
        it "parses a simple template argument" do
            assert_equal ["base",['10']], ModelKit::Types.parse_template("base<10>")
        end
        it "parses multiple template arguments" do
            assert_equal ["base",['10', '20', 'test']], ModelKit::Types.parse_template("base<10,20,test>")
        end
        it "parses recursive template arguments" do
            assert_equal ["base",['10', '20<foo>', 'test<foo,test<bar>>']], ModelKit::Types.parse_template("base<10,20<foo>,test<foo,test<bar>>>")
        end
        it "can handle a full name if full_name is true" do
            assert_equal ["/std/base",['10', '20<foo>', 'test<foo,test<bar>>']], ModelKit::Types.parse_template("/std/base<10,20<foo>,test<foo,test<bar>>>", full_name: true)
        end
        it "raises InvalidTypeNameError if a template open marker is not closed" do
            assert_raises(ModelKit::Types::InvalidTypeNameError) do
                ModelKit::Types.parse_template("invalid<typename")
            end
        end
        it "raises InvalidTypeNameError if there are too many template groups closing markers" do
            assert_raises(ModelKit::Types::InvalidTypeNameError) do
                ModelKit::Types.parse_template("invalid</typename>>")
            end
        end
    end
end

