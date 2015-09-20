
class DefaultFilter < FilterSkel

	@@rules = {
		'.+' => 'load_page',
	}

	def self.rules
		@@rules
	end

	def process(arg)
		Msg.blue "#{self.class}.#{__method__}(#{arg})"
		self.send(
			arg[:action_name].to_sym,
			arg[:data]
		)
	end
	
	# default action
	def load_page(arg)
		Msg.blue "#{self.class}.#{__method__}(#{arg})"
		Book.plugin(
			name: 'www/load',
			data: arg[:uri],
			uuid: SecureRandom.uuid,
		)	
	end
	
end
