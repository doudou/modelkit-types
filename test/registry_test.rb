require 'test_helper'

module ModelKit::Types
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

        describe "#size" do
            it "returns the number of type names registered" do
                assert_equal 1, registry.size
                registry.create_type '/Test'
                assert_equal 2, registry.size
                registry.create_alias "/Alias", "/Test"
                assert_equal 3, registry.size
            end
        end

        describe "#dup" do
            it "creates a copy of the whole registry" do
                copy = registry.dup
                refute_same copy, registry
                copy.each(with_aliases: true) do |name, type|
                    registry_type = registry.get(name)
                    refute_same registry_type, type
                    assert_equal registry_type, type
                end
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
            it "creates an alias if the element name is an alias itself" do
                registry.create_alias '/Alias', '/int'
                array_t = registry.build('/Alias[10]')
                assert_equal '/int[10]', array_t.name
                assert_same array_t, registry.get('/int[10]')
            end
            it "knows how to build a container" do
                container_t = registry.build('/container_t</int>')
                assert_same container_model, container_t.container_model
                assert_same int_t, container_t.deference
            end
            it "creates an alias if the container element is itself an alias" do
                registry.create_alias '/Alias', '/int'
                container_t = registry.build('/container_t</Alias>')
                assert_equal '/container_t</int>', container_t.name
                assert_same container_t, registry.get('/container_t</Alias>')
                assert_same container_t, registry.get('/container_t</int>')
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

        describe "container registration" do
            it "creates and registers a new model" do
                container_m = registry.create_container_model '/test'
                assert_same container_m, registry.container_model_by_name('/test')
                assert_equal ContainerType, container_m.superclass
            end
            it "registers a new model" do
                container_m = ContainerType.new_submodel typename: '/container'
                registry.register_container_model container_m
                assert_same container_m, registry.container_model_by_name('/container')
            end
            it "raises DuplicateTypeNameError if a container with the same name already exists" do
                container_m = ContainerType.new_submodel typename: '/container'
                registry.register_container_model container_m
                assert_raises(DuplicateTypeNameError) do
                    registry.register_container_model container_m
                end
            end
            it "enumerates the available containers" do
                assert_equal [], registry.each_available_container_model.to_a
                container_m = ContainerType.new_submodel typename: '/container'
                registry.register_container_model container_m
                assert_equal [container_m], registry.each_available_container_model.to_a
            end
        end

        describe "#register" do
            it "registers a new type" do
                type = Type.new_submodel(typename: '/test')
                registry.register(type)
                assert_same type, registry.get('/test')
                assert_same registry, type.registry
            end
            it "raises InvalidTypeNameError if the type has no name" do
                type = Type.new_submodel
                assert_raises(InvalidTypeNameError) do
                    registry.register(type)
                end
            end
            it "raises InvalidTypeNameError if the type has an invalid name" do
                type = Type.new_submodel(typename: 'invalid')
                assert_raises(InvalidTypeNameError) do
                    registry.register(type)
                end
            end
            it "allows to register the type under a different name than its own" do
                type = Type.new_submodel(typename: '/test')
                registry.register(type, name: '/other')
                assert_same type, registry.get('/other')
                refute registry.include?('/test')
            end
            it "raises DuplicateTypeNameError if the type name is already in use" do
                type = Type.new_submodel(typename: '/test')
                registry.register(type)
                assert_raises(DuplicateTypeNameError) do
                    registry.register(type)
                end
            end
            it "raises NotFromThisRegistryError if the type is already registered elsewhere" do
                type = Type.new_submodel(typename: '/test')
                Registry.new.register(type)
                assert_raises(NotFromThisRegistryError) do
                    registry.register(type)
                end
            end
        end

        describe "#add" do
            it "ensures that the type is defined on self" do
                type = Type.new_submodel(typename: '/test')
                Registry.new.register(type)
                flexmock(registry).should_receive(:merge).once.
                    with(->(r) { [type] == r.each.to_a }).
                    pass_thru
                registry.add(type)
                assert_equal type, registry.get('/test')
            end
            it "does nothing if the type is already in the registry" do
                type = Type.new_submodel(typename: '/test')
                registry.register(type)
                flexmock(registry).should_receive(:merge).never
                registry.add(type)
                assert_equal type, registry.get('/test')
            end
        end

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

            it "raises InvalidSizeSpecifiedError if a given size is smaller than the type's minimum size" do
                flexmock(int_t).should_receive(:apply_resize).and_return(256)
                assert_raises(InvalidSizeSpecifiedError) do
                    registry.resize(int_t => 128)
                end
            end
        end

        describe "#create_opaque" do
            it "creates a type model with opaque set" do
                type = registry.create_opaque '/opaque'
                assert Type, type.superclass
                assert type.opaque?
                assert_same type, registry.get('/opaque')
            end
            it "passes extra options to the underlying type creation" do
                flexmock(registry).should_receive(:create_type).
                    with('/opaque', size: 10, opaque: true, extra: :options).
                    once
                registry.create_opaque '/opaque', size: 10, extra: :options
            end
        end

        describe "#create_null" do
            it "creates a type model with null set" do
                type = registry.create_null '/null'
                assert Type, type.superclass
                assert type.null?
                assert_same type, registry.get('/null')
            end
            it "passes extra options to the underlying type creation" do
                flexmock(registry).should_receive(:create_type).
                    with('/null', size: 10, null: true, extra: :options).
                    once
                registry.create_null '/null', size: 10, extra: :options
            end
        end

        describe "#create_character" do
            it "creates and registers a character type model" do
                type = registry.create_null '/char'
                assert_equal '/char', type.name
                assert CharacterType, type.superclass
                assert_same type, registry.get('/char')
            end
            it "passes extra options to the underlying type creation" do
                char_t = CharacterType.new_submodel(typename: '/char')
                flexmock(CharacterType).should_receive(:new_submodel).
                    with(typename: '/char', registry: registry, size: 10, extra: :options).
                    once.
                    and_return(char_t)
                registry.create_character '/char', size: 10, extra: :options
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
                type = registry.create_container('/std/vector', int_t)
                assert(type <= container_t)
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

            it "raises NoMethodError if trying to access an invalid method on the enum builder" do
                assert_raises(NoMethodError) do
                    registry.create_enum('/NewEnum') do |enum_t|
                        enum_t.VAL0('10')
                    end
                end
                refute registry.include?('/NewEnum')
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
            it "does not set the size if the element has no size" do
                element_t = registry.create_null '/nil_size'
                array_t = registry.create_array element_t, 20
                assert_nil array_t.size
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
                        t.add('field0', f0_t, offset: 0)
                        t.add('field1', f0_t, offset: 20)
                    end
                    assert_equal(20 + f0_t.size, compound_t.size)
                end

                it "allows to override the size" do
                    compound_t = registry.create_compound('/NewCompound', size: 2000) do |t|
                        t.add('field0', f0_t, offset: 0)
                        t.add('field1', f0_t, offset: 20)
                    end
                    assert_equal(2000, compound_t.size)
                end

                it "raises NoMethodError if trying to call a method that does not exist on the builder" do
                    assert_raises(NoMethodError) do
                        registry.create_compound('/NewCompound', size: 2000) do |t|
                            t.does_not_exist
                        end
                    end
                    refute registry.include?('/NewCompound')
                end

                describe "the assignation syntax" do
                    it "calls #add with the current offset as offset" do
                        compound_t = registry.create_compound('/NewCompound') do |t|
                            t.field0 = f0_t
                            t.skip 10
                            flexmock(t).should_receive('add').with('field1', f0_t).
                                pass_thru
                            t.field1 = f0_t
                        end
                        assert_equal 10 + f0_t.size, compound_t.get('field1').offset
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
                            t.add('field0', f0_t)
                            t.skip 10
                            t.add('field1', f0_t)
                        end
                        assert_equal 10 + f0_t.size, compound_t.get('field1').offset
                    end
                    it "allows to override the offset" do
                        compound_t = registry.create_compound('/NewCompound') do |t|
                            t.add('field0', f0_t)
                            t.skip 10
                            t.add('field1', f0_t, offset: 2000)
                        end
                        assert_equal 2000, compound_t.get('field1').offset
                    end
                    it "allows to override the skip" do
                        compound_t = registry.create_compound('/NewCompound') do |t|
                            t.add('field0', f0_t)
                            t.add('field1', f0_t, skip: 10)
                            t.add('field2', f0_t)
                        end
                        assert_equal 20, compound_t.get('field1').offset
                        assert_equal 10, compound_t.get('field1').skip
                        assert_equal 50, compound_t.get('field2').offset
                    end
                    it "overrides if following offsets do not match the expectations" do
                        registry.create_compound('/NewCompound') do |t|
                            t.add('field0', f0_t)
                            t.add('field1', f0_t, offset: 100, skip: 10)
                            assert_raises(ArgumentError) do
                                t.add('field2', f0_t, offset: 120)
                            end
                        end
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

            it "raises if an alias on the argument resolves to a different type on the receiver" do
                t0 = r0.create_type '/Type'
                r0.create_alias '/Alias', t0
                r1.create_type '/Alias', null: true
                assert_raises(InvalidMergeError) { r1.merge(r0) }
            end
        end

        describe "#each" do
            attr_reader :r0
            before do
                @r0 = Registry.new
            end

            describe "without aliases" do
                it "enumerates the registry types" do
                    t = r0.create_type '/Type'
                    assert_equal [t], r0.each.to_a
                end
                it "enumerates an aliased type only once" do
                    t = r0.create_type '/Type'
                    r0.create_alias '/Alias', t
                    assert_equal [t], r0.each.to_a
                end
            end
        end

        describe "#minimal" do
            subject { Registry.new }
            let(:type) { subject.create_type '/test' }

            it "copies the type and its missing dependencies to the new registry" do
                target_registry = nil
                flexmock(type).should_receive(:copy_to).with(->(r) { !r.equal?(subject) && (target_registry = r) }).
                    once.pass_thru
                subject.minimal(type)
            end

            it "copies the aliases to the type if with_aliases is set" do
                subject.create_alias '/alias', type
                result = subject.minimal(type, with_aliases: true)
                assert_equal '/test', result.get('/alias').name
            end

            it "does not copy the aliases to the type if with_aliases is false" do
                subject.create_alias '/alias', type
                result = subject.minimal(type, with_aliases: false)
                assert !result.include?('/alias')
            end
        end

        describe "#minimal_without" do
            attr_reader :registry, :test_t, :other_t, :test_compound_t, :other_compound_t
            before do 
                @registry = Registry.new
                @test_t = registry.create_type '/Test'
                @other_t = registry.create_type '/Other'
                @test_compound_t = registry.create_compound '/TestCompound' do |c|
                    c.add 'test', '/Test'
                end
                @other_compound_t = registry.create_compound '/OtherCompound' do |c|
                    c.add 'test', '/Other'
                end
            end

            it "copies everything that is not self-contained in the given set of types" do
                target = registry.minimal_without([test_t, test_compound_t])
                assert_equal [other_t, other_compound_t], target.each.sort_by(&:name)
            end
            it "does copy arguments if some other types depend on them" do
                target = registry.minimal_without([test_t])
                assert_equal [other_t, other_compound_t, test_t, test_compound_t], target.each.sort_by(&:name)
            end
            it "does copy dependencies of an excluded type" do
                target = registry.minimal_without([test_compound_t])
                assert_equal [other_t, other_compound_t, test_t], target.each.sort_by(&:name)
            end
            it "copies aliases to the copied types by default" do
                registry.create_alias '/TestAlias', test_t
                registry.create_alias '/OtherAlias', other_t
                target = registry.minimal_without([test_t, test_compound_t])
                assert_equal [['/Other', other_t], ['/OtherAlias', other_t], ['/OtherCompound', other_compound_t]], target.each(with_aliases: true).sort_by(&:first)
            end
            it "does not copy aliases if with_aliases is false" do
                registry.create_alias '/TestAlias', test_t
                registry.create_alias '/OtherAlias', other_t
                target = registry.minimal_without([test_t, test_compound_t], with_aliases: false)
                assert_equal [['/Other', other_t], ['/OtherCompound', other_compound_t]], target.each(with_aliases: true).sort_by(&:first)
            end
        end

        describe "#export_to_ruby" do
            it "sets up export on the given namespace module" do
                registry.create_type '/Test'
                root = Module.new
                registry.export_to_ruby(root)
                assert_equal registry.get('/Test'), root.Test
            end
        end

        describe ".import" do
            attr_reader :tlb_path, :expected_registry
            before do
                @tlb_path = Pathname.new(__dir__) + "io" + "cxx_import_tests" + "enums.tlb"
                @expected_registry = Registry.from_xml(tlb_path.read)
            end
            it "creates a registry and imports into it" do
                flexmock(Registry).new_instances.should_receive(:import).
                    with(tlb_path, kind: 'auto').
                    once.
                    pass_thru
                registry = Registry.import(tlb_path)
                assert registry.same_types?(expected_registry)
            end
            it "passes extra options" do
                flexmock(Registry).new_instances.should_receive(:import).
                    with(tlb_path, kind: 'auto', extra: :options).
                    once
                Registry.import(tlb_path, extra: :options)
            end
        end

        describe "#import" do
            attr_reader :tlb_path, :registry, :expected_registry
            before do
                @tlb_path = Pathname.new(__dir__) + "io" + "cxx_import_tests" + "enums.tlb"
                @expected_registry = Registry.from_xml(tlb_path.read)
                @registry = Registry.new
            end
            it "imports into self" do
                registry.import(tlb_path)
                assert registry.same_types?(expected_registry)
            end
            it "raises ArgumentError if the file's extension is unknown" do
                e = assert_raises(ArgumentError) do
                    registry.import("#{tlb_path}.unknown", extra: :option)
                end
                assert_equal "cannot guess file type for #{tlb_path}.unknown: unknown extension '.unknown'", e.message
            end
            it "raises ArgumentError if the file's guessed type has no importer" do
                flexmock(Registry).should_receive(:guess_type).
                    and_return("file_type_without_importer")

                e = assert_raises(ArgumentError) do
                    registry.import(tlb_path, extra: :option)
                end
                assert_equal "no importer defined for #{tlb_path}, detected as file_type_without_importer", e.message
            end
        end

        describe "#export" do
            attr_reader :tlb_path, :registry, :expected_registry
            before do
                @tlb_path = Pathname.new(__dir__) + "io" + "cxx_import_tests" + "enums.tlb"
                @registry = Registry.from_xml(tlb_path.read)
            end
            it "exports self" do
                xml = registry.export('tlb')
                assert registry.same_types?(Registry.from_xml(xml))
            end
            it "raises ArgumentError if the exporter kind is unknown" do
                e = assert_raises(ArgumentError) do
                    registry.export("unknown")
                end
                assert_equal "no exporter defined for unknown", e.message
            end
        end

        describe "#clear_aliases" do
            it "removes aliases from the registry" do
                registry = Registry.new
                test_t = registry.create_type '/test'
                registry.create_alias '/alias', test_t
                registry.clear_aliases
                assert_equal [['/test', test_t]], registry.each(with_aliases: true).to_a
            end
        end
    end
end

