# coding: utf-8

class RuWikipediaOrgFilter < FilterSkel

	@@rules = {
		'^https:\/\/ru\.wikipedia\.org\/wiki\/[\w%]+' => 'article',
		'^https:\/\/ru\.wikipedia\.org\/w\/index\.php\?title=[\w%]+&printable=yes' => 'article_printable',
	}

	def article(arg)
		Msg.blue "#{self.class}.#{__method__}(#{arg})"
		#https://ru.wikipedia.org/wiki/%D0%A2%D0%B5%D0%BE%D1%80%D0%B8%D1%8F_%D1%81%D1%82%D1%80%D1%83%D0%BD
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
