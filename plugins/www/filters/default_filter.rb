
class DefaultFilter < FilterSkel

	@@rules = {
		'.+' => 'load_page',
	}
	
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
