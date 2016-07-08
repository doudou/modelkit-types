require 'facets/string/snakecase'
require 'facets/string/camelcase'
module ModelKit::Types
    module RegistryExport
        class Namespace < Module
            include RegistryExport
        end

        class NotFound < RuntimeError; end

        attr_reader :registry
        attr_reader :typename_prefix
        attr_reader :filter_block

        def reset_registry_export(registry = self.registry, filter_block = self.filter_block)
            @registry = registry
            @filter_block = filter_block
            @typename_prefix = '/'
            @__typestore_cache ||= Hash.new
            @__typestore_cache.clear
        end

        def disable_registry_export
            reset_registry_export(Registry.new, nil)
        end

        def initialize_registry_export_namespace(mod, name)
            @registry = mod.registry
            @typename_prefix = "#{mod.typename_prefix}#{name}/"
            @filter_block = mod.filter_block
        end

        def to_s
            "#{typename_prefix}*"
        end

        def pretty_print(pp)
            pp.text to_s
        end

        def self.setup_subnamespace(parent, mod, name)
            mod.extend RegistryExport
            mod.initialize_registry_export_namespace(parent, name)
        end

        def self.template_args_to_type_name(args)
            if !args.empty?
                args = args.map do |v|
                    if v.respond_to?(:name)
                        v.name
                    else v.to_s
                    end
                end
                "<#{args.join(",")}>"
            end
        end

        def self.each_candidate_name(relaxed_naming, m, *args)
            template_args = template_args_to_type_name(args)
            yield("#{m}#{template_args}")
            return if !relaxed_naming
            yield("#{m.snakecase}#{template_args}")
            yield("#{m.camelcase}#{template_args}")
        end


        def self.find_namespace(relaxed_naming, typename_prefix, registry, m, *args)
            each_candidate_name(relaxed_naming, m, *args) do |basename|
                if registry.each("#{typename_prefix}#{basename}/").first
                    return basename
                end
            end

            return if !relaxed_naming

            # Try harder ... for weird naming conventions ... but that's costly
            prefix = ModelKit::Types.typename_parts(typename_prefix)
            template_args = template_args_to_type_name(args)
            basename = "#{m}#{template_args}".snakecase
            registry.each(typename_prefix) do |type|
                name = type.typename_parts
                next if name[0, prefix.size] != prefix
                if name[prefix.size].snakecase == basename
                    return name[prefix.size]
                end
            end
            nil
        end

        def self.find_type(relaxed_naming, typename_prefix, registry, m, *args)
            each_candidate_name(relaxed_naming, m, *args) do |basename|
                if registry.include?(typename = "#{typename_prefix}#{basename}")
                    return registry.get(typename)
                end
            end

            return if !relaxed_naming

            # Try harder ... for weird naming conventions ... but that's costly
            template_args = template_args_to_type_name(args)
            registry.each(typename_prefix) do |type|
                if type.name =~ /^#{Regexp.quote(typename_prefix)}[^\/]+$/o
                    if type.basename.snakecase == "#{m.to_s.snakecase}#{template_args}"
                        return type
                    end
                end
            end
            nil
        end

        def resolve_call_from_exported_registry(relaxed_naming, m, *args)
            @__typestore_cache ||= Hash.new
            if type = @__typestore_cache[[m, args]]
                return type
            elsif type = RegistryExport.find_type(relaxed_naming, typename_prefix, registry, m, *args)
                exported_type =
                    if filter_block
                        filter_block.call(type)
                    else
                        type
                    end
                @__typestore_cache[[m, args]] = exported_type
                if exported_type
                    RegistryExport.setup_subnamespace(self, exported_type, type.basename)
                end
                exported_type
            elsif basename = RegistryExport.find_namespace(relaxed_naming, typename_prefix, registry, m, *args)
                ns = Namespace.new
                RegistryExport.setup_subnamespace(self, ns, basename)
                @__typestore_cache[[name, []]] = ns
            end
        end

        def method_missing(m, *args, &block)
            if type = resolve_call_from_exported_registry(false, m.to_s, *args)
                return type
            else
                template_args = RegistryExport.template_args_to_type_name(args)
                raise NotFound, "cannot find a type named #{typename_prefix}#{m}#{template_args} in registry"
            end
        end

        def const_missing(name)
            if type = resolve_call_from_exported_registry(true, name.to_s)
                return type
            else
                raise NotFound, "cannot find a type named #{name}, or a type named like that after a CamelCase or snake_case conversion, in #{self}"
            end
        end
    end
end

