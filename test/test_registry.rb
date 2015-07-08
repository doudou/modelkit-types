require 'typestore/test'

module TypeStore
    describe Registry do
        attr_reader :registry, :int_t
        before do
            @registry = Registry.new
            @int_t = registry.create_type '/int'
        end

        describe "#alias" do
            it "registers a new name for an existing type" do
                registry.create_alias "/my_own_and_only_int", "/int"
                assert_same int_t, registry.get("/my_own_and_only_int")
                assert_equal(["/my_own_and_only_int"], registry.aliases_of(int_t))
            end
        end


        describe ".guess_type" do
            it "raises UnknownFileTypeError if there is no importer associated with the file type" do
                assert_raises(UnknownFileTypeError) { Registry.guess_type("bla.1") }
            end
            it "returns the file type if there is an importer" do
                assert_equal("c", Registry.guess_type("blo.c"))
                assert_equal("c", Registry.guess_type("blo.h"))
                assert_equal("tlb", Registry.guess_type("blo.tlb"))
            end
        end

        describe "#get" do
            it "returns the type" do
                assert_same int_t, registry.get('/int')
            end
            it "raises NotFound if there is no type with this name in the registry" do
                assert_raises(NotFound) { registry.get('/does_not_exist') }
            end
        end

        describe "#build" do
            attr_reader :container_model
            before do
                @container_model = ContainerType.new_submodel typename: '/container_t'
                registry.register_container_model(@container_model)
            end
            it "returns an existing type" do
                assert_same int_t, registry.build('/int')
            end
            it "knows how to build an array" do
                array_t = registry.build('/int[10]')
                assert_equal 10, array_t.length
                assert_same int_t, array_t.deference
            end
            it "knows how to build a container" do
                container_t = registry.build('/container_t</int>')
                assert_same container_model, container_t.container_model
                assert_same int_t, container_t.deference
            end
            it "ignores subsequent arguments when building containers" do
                container_t = registry.build('/container_t</int,10>')
                assert_same container_model, container_t.container_model
                assert_same int_t, container_t.deference
            end
            it "recursively builds types" do
                type = registry.build('/container_t</int>[20]')
                assert(type <= ArrayType)
                container_t = type.deference
                assert(container_t <= container_model)
                assert_same int_t, container_t.deference
            end
            it "raises NotFound if the array element type does not exist" do
                assert_raises(NotFound) { registry.build('/does_not_exist[10]') }
            end
            it "raises NotFound if the container type does not exist" do
                container_typename = '/does_not_exist'
                error = assert_raises(NotFound) { registry.build("#{container_typename}</int>") }
                assert error.message =~ /#{container_typename}/
            end
            it "raises NotFound if the container element type does not exist" do
                assert_raises(NotFound) { registry.build('/container_t</does_not_exist>') }
            end
        end

        # describe "#import" do
        #     it "raises ImportFailed if the file does not exist" do
        #         assert_raises(ArgumentError) { registry.import("bla.c") }
        #     end
        #     it "raises the importer's exception if the importer fails" do
        #         assert_raises(ArgumentError) { registry.import(testfile) }
        #     end
        #     it "passes the options to the importer" do
        #         registry = Registry.new
        #         testfile = File.join(SRCDIR, "test_cimport.h")
        #         registry.import(testfile, nil, :include => [ File.join(SRCDIR, '..') ], :define => [ 'GOOD' ])
        #     end

        #     it "merges the result into the receiver is merge is true" do
        #         testfile = File.join(SRCDIR, "test_cimport.h")
        #         registry.import(testfile, nil, :rawflags => [ "-I#{File.join(SRCDIR, '..')}", "-DGOOD" ])
        #         registry.import(testfile, nil, :merge => true, :rawflags => [ "-I#{File.join(SRCDIR, '..')}", "-DGOOD" ])
        #     end
        # end

        describe "#resize" do
            attr_reader :compound_t, :array_t, :compound_array_t
            before do
                dummy_t = registry.create_type '/dummy', size: 10
                @compound_t = registry.create_compound '/Test' do |t|
                    t.add 'before', dummy_t, offset: 0
                    t.add 'resized', int_t, offset: 10
                    t.add 'after', dummy_t, offset: 20
                end
                @array_t = registry.create_array int_t, 10
                @compound_array_t = registry.create_array compound_t, 10
                registry.resize(int_t => 64)
            end

            it "resizes the specified type" do
                assert_equal 64, int_t.size
            end

            it "accepts a type name as argument" do
                registry.resize('/int' => 20)
                assert_equal 20, int_t.size
            end

            it "raises NotFromThisRegistryError if given a type from another registry" do
                int = Registry.new.create_type '/int'
                assert_raises(NotFromThisRegistryError) { registry.resize(int => 20) }
            end

            it "modifies the registry's compound types field offsets to make room for the new size" do
                assert_equal 74, compound_t.get('after').offset
            end

            it "modifies the registry's compound types size to make room for the new size" do
                assert_equal 84, compound_t.size
            end

            it "modifies the registry's array types size to make room for the new size" do
                assert_equal 64 * 10, array_t.size
            end

            it "handles recursive resizes" do
                assert_equal 84 * 10, compound_array_t.size
            end
        end

        describe "#create_container" do
            attr_reader :container_t
            before do
                @container_t = ContainerType.new_submodel(typename: '/std/vector')
                registry.register_container_model(container_t)
            end

            it "creates a container of the specified container kind and element type" do
                vector_t = registry.create_container(container_t, int_t)
                assert(vector_t <= container_t)
                assert_same(int_t, vector_t.deference)
            end
            it "generates the type name automatically" do
                vector_t = registry.create_container(container_t, int_t)
                assert_equal "#{container_t.name}<#{int_t.name}>", vector_t.name
            end
            it "allows to override the type name" do
                vector_t = registry.create_container(container_t, int_t, typename: '/test')
                assert_equal '/test', vector_t.name
            end
            it "validates the explicitely provided type name" do
                assert_raises(InvalidTypeNameError) do
                    registry.create_container(container_t, int_t, typename: 'bla')
                end
            end
            it "accepts to be given the container kind by name" do
                vector_t = registry.create_container('/std/vector', int_t)
            end
            it "raises NotFound if the container kind name does not exist" do
                assert_raises(NotFound) do
                    registry.create_container('/this_is_an_unknown_container', '/int')
                end
            end
            it "accepts to be given the element type by name" do
                vector_t = registry.create_container(container_t, '/int')
                assert_same(int_t, vector_t.deference)
            end
            it "raises NotFromThisRegistryError if the element type is not from the receiver" do
                assert_raises(NotFromThisRegistryError) do
                    registry.create_container(container_t, Registry.new.create_type('/other_registry'))
                end
            end
            it "raises NotFound if the element type name does not exist" do
                assert_raises(NotFound) do
                    registry.create_container(container_t, '/does_not_exist')
                end
            end
        end

        describe "#create_enum" do
            it "creates the specified enum" do
                t = registry.create_enum('/NewEnum') do |enum_t|
                    enum_t.VAL0
                    enum_t.VAL1 = -1
                    enum_t.VAL2
                end
                assert_equal({:VAL0 => 0, :VAL1 => -1, :VAL2 => 0}, t.symbol_to_value)
            end
            it "refuses to use an existing name" do
                registry.create_enum('/NewEnum') { |enum_t| enum_t.VAL0 }
                assert_raises(DuplicateTypeNameError) do
                    registry.create_enum('/NewEnum') { |enum_t| enum_t.VAL0 }
                end
            end
            it "validates the type name" do
                assert_raises(InvalidTypeNameError) do
                    registry.create_enum('test') { |enum_t| }
                end
            end
        end

        describe "#create_array" do
            attr_reader :array_t, :element_t
            before do
                @element_t = registry.create_type '/element', size: 10
            end
            it "creates an array of the specified element type" do
                array_t = registry.create_array element_t, 20
                assert_same element_t, array_t.deference
            end
            it "generates the type name automatically" do
                array_t = registry.create_array element_t, 20
                assert_equal "#{element_t.name}[20]", array_t.name
            end
            it "allows to override the type name" do
                array_t = registry.create_array element_t, 20, typename: '/test'
                assert_equal '/test', array_t.name
            end
            it "validates the explicitely provided type name" do
                assert_raises(InvalidTypeNameError) do
                    registry.create_array element_t, 20, typename: 'test'
                end
            end
            it "autocomputes the size if not given" do
                array_t = registry.create_array element_t, 20
                assert_equal(20*element_t.size, array_t.size)
            end
            it "allows to override the size" do
                array_t = registry.create_array element_t, 20, size: 500
                assert_equal(500, array_t.size)
            end
            it "accepts a type name as element type" do
                array_t = registry.create_array '/element', 20
                assert_same element_t, array_t.deference
            end
            it "raises NotFromThisRegistryError if the given element type is from another registry" do
                element = Registry.new.create_type '/other_registry'
                assert_raises(NotFromThisRegistryError) do
                    registry.create_array element, 20
                end
            end
        end

        describe "#create_compound" do
            it "sets the type name" do
                compound_t = registry.create_compound '/test'
                assert_equal '/test', compound_t.name
            end
            it "validates the provided type name" do
                assert_raises(InvalidTypeNameError) do
                    registry.create_compound 'test'
                end
            end
            describe "the builder block" do
                attr_reader :f0_t, :compound_t
                before do
                    @f0_t = registry.create_type '/f0', size: 20
                end

                it "sets the size of the compound to the last field plus size" do
                    compound_t = registry.create_compound('/NewCompound') do |t|
                        t.add('field0', f0_t, offset: 20)
                    end
                    assert_equal(20 + f0_t.size, compound_t.size)
                end

                it "allows to override the size" do
                    compound_t = registry.create_compound('/NewCompound', size: 2000) do |t|
                        t.add('field0', f0_t, offset: 20)
                    end
                    assert_equal(2000, compound_t.size)
                end

                describe "the assignation syntax" do
                    it "calls #add with the current offset as offset" do
                        compound_t = registry.create_compound('/NewCompound') do |t|
                            t.skip 10
                            flexmock(t).should_receive('add').with('field0', f0_t).
                                pass_thru
                            t.field0 = f0_t
                        end
                        assert_equal 10, compound_t.get('field0').offset
                    end
                end
                describe "the #add syntax" do
                    it "adds fields" do
                        compound_t = registry.create_compound('/NewCompound') do |t|
                            t.add('f0', f0_t)
                        end
                        assert_equal f0_t, compound_t.get('f0').type
                    end
                    it "sets the offset to the current offset" do
                        compound_t = registry.create_compound('/NewCompound') do |t|
                            t.skip 10
                            t.add('field0', f0_t)
                        end
                        assert_equal 10, compound_t.get('field0').offset
                    end
                    it "allows to override the offset" do
                        compound_t = registry.create_compound('/NewCompound') do |t|
                            t.add('field0', f0_t, offset: 20)
                        end
                        assert_equal 20, compound_t.get('field0').offset
                    end
                end
            end
        end

        describe "#merge" do
            attr_reader :r0, :r1
            before do
                @r0 = Registry.new
                @r1 = Registry.new
            end

            it "raises if two types with the same name cannot be merged" do
                t0 = r0.create_type '/Type'
                r0.create_type '/T0'
                t1 = r1.create_type '/Type'
                r1.create_type '/T1'
                flexmock(t0).should_receive(:validate_merge).with(t1).and_raise(InvalidMergeError)
                assert_raises(InvalidMergeError) { r0.merge(r1) }
                assert !r0.include?('/T1')
            end

            it "copies mising types over" do
                t0 = r0.create_type '/Type'
                flexmock(t0).should_receive(:copy_to).with(r1).once
                r1.merge(r0)
            end

            it "copies aliases of new types" do
                t0 = r0.create_type '/Type'
                r0.create_alias '/Alias', t0
                r1.merge(r0)
                assert_equal t0, r1.get('/Alias')
            end

            it "copies aliases of existing types" do
                t0 = r0.create_type '/Type'
                r0.create_alias '/Alias', t0
                r1.create_type '/Type'
                r1.merge(r0)
                assert_equal t0, r1.get('/Alias')
            end

            it "calls #merge on common types" do
                t0 = r0.create_type '/Type'
                t1 = r1.create_type '/Type'
                flexmock(t1).should_receive(:merge).with(t0).once
                r1.merge(r0)
            end
        end

        #def test_registry_iteration
        #    reg = make_registry

        #    values = Typelib.log_silent { reg.each.to_a }
        #    refute_equal(0, values.size)
        #    assert(values.include?(reg.get("/int")))
        #    assert(values.include?(reg.get("/EContainer")))

        #    values = reg.each(:with_aliases => true).to_a
        #    refute_equal(0, values.size)
        #    assert(values.include?(["/EContainer", reg.get("/EContainer")]))

        #    values = reg.each('/NS1').to_a
        #    assert_equal(6, values.size, values.map(&:name))
        #end

        #def test_validate_xml
        #    test = "malformed_xml"
        #    assert_raises(ArgumentError) { Registry.from_xml(test) }

        #    test = "<typelib><invalid_element name=\"name\" size=\"0\" /></typelib>"
        #    assert_raises(ArgumentError) { Registry.from_xml(test) }

        #    test = "<typelib><opaque name=\"name\" /></typelib>"
        #    assert_raises(ArgumentError) { Registry.from_xml(test) }

        #    test = "<typelib><opaque name=\"invalid type name\" size=\"0\" /></typelib>"
        #    assert_raises(ArgumentError) { Registry.from_xml(test) }
        #end

        #def test_merge_keeps_metadata
        #    reg = Typelib::Registry.new
        #    Typelib::Registry.add_standard_cxx_types(reg)
        #    type = reg.create_compound '/Test' do |c|
        #        c.add 'field', 'double'
        #    end
        #    type.metadata.set('k', 'v')
        #    type.field_metadata['field'].set('k', 'v')
        #    new_reg = Typelib::Registry.new
        #    new_reg.merge(reg)
        #    new_type = new_reg.get('/Test')
        #    assert_equal [['k', ['v']]], new_type.metadata.each.to_a
        #    assert_equal [['k', ['v']]], new_type.field_metadata['field'].each.to_a
        #end

        #def test_minimal_keeps_metadata
        #    reg = Typelib::Registry.new
        #    Typelib::Registry.add_standard_cxx_types(reg)
        #    type = reg.create_compound '/Test' do |c|
        #        c.add 'field', 'double'
        #    end
        #    type.metadata.set('k', 'v')
        #    type.field_metadata['field'].set('k', 'v')
        #    new_reg = reg.minimal('/Test')
        #    new_type = new_reg.get('/Test')
        #    assert_equal [['k', ['v']]], new_type.metadata.each.to_a
        #    assert_equal [['k', ['v']]], new_type.field_metadata['field'].each.to_a
        #end

        #def test_create_opaque_raises_ArgumentError_if_the_name_is_already_used
        #    reg = Typelib::Registry.new
        #    reg.create_opaque '/Test', 10
        #    assert_raises(ArgumentError) { reg.create_opaque '/Test', 10 }
        #end

        #def test_create_null_raises_ArgumentError_if_the_name_is_already_used
        #    reg = Typelib::Registry.new
        #    reg.create_null '/Test'
        #    assert_raises(ArgumentError) { reg.create_null '/Test' }
        #end

        #def test_reverse_depends_resolves_recursively
        #    reg = Typelib::Registry.new
        #    Typelib::Registry.add_standard_cxx_types(reg)
        #    compound_t = reg.create_compound '/C' do |c|
        #        c.add 'field', 'double'
        #    end
        #    vector_t = reg.create_container '/std/vector', compound_t
        #    array_t  = reg.create_array vector_t, 10
        #    assert_equal [compound_t, array_t, vector_t].to_set,
        #        reg.reverse_depends(compound_t).to_set
        #end

        #def test_remove_removes_the_types_and_its_dependencies
        #    reg = Typelib::Registry.new
        #    Typelib::Registry.add_standard_cxx_types(reg)
        #    compound_t = reg.create_compound '/C' do |c|
        #        c.add 'field', 'double'
        #    end
        #    vector_t = reg.create_container '/std/vector', compound_t
        #    reg.create_array vector_t, 10
        #    reg.remove(compound_t)
        #    assert !reg.include?("/std/vector</C>")
        #    assert !reg.include?("/std/vector</C>[10]")
        #end
    end
end
