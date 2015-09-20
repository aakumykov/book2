# coding: utf-8

class RuWikipediaOrgFilter < FilterSkel

	@@rules = {
		'^https:\/\/ru\.wikipedia\.org\/wiki\/[\w%]+' => 'article',
		'^https:\/\/ru\.wikipedia\.org\/w\/index\.php\?title=[\w%]+&printable=yes' => 'article_printable',
	}

	def article(arg)
		Msg.blue "#{self.class}.#{__method__}(#{arg})"
		Book.plugin(
			name: 'www/load',
			data: arg[:uri],
			uuid: SecureRandom.uuid,
		)
	end

	def article_printable(arg)
		Msg.blue "#{self.class}.#{__method__}(#{arg})"
	end
end
