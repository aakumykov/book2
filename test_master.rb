# coding: utf-8
system 'clear'
require 'awesome_print'

class RuleHolder
	def initialize(dir)
		@all_rules = {}

		self.loadRules(dir)
	end

	def loadRules(dir)

		all_rules = {}

		Dir.entries(dir).each {|file_name|

			if file_name.match(/^\w+_filters\.rb$/) then
				
				Object.send(:remove_const,:RULES) if Object.constants.include?(:RULES)

				file = dir+'/'+file_name
				if (File.exists?(file) and File.readable?(file)) then
					require file
				else
					next
				end

				puts "============ RULES in #{file_name} ============="
				
				RULES.each { |key,value|
					if all_rules.key?(key) then
						puts "Игнорируется дубликат '#{key}' со значением '#{value}'."
					else
						all_rules[key] = value
					end
				}
			end
		}

		return all_rules
	end

	def getRuleFor(uri)
		
	end
end


rh = RuleHolder.new(Dir.pwd)

