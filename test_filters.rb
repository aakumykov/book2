# coding: utf-8

RULES = {
	'opennet.ru' => 'opennet_main',
	'www.opennet.ru' => 'opennet_main_www',
	'pda.opennet.ru' => 'opennet_main_pda',
	'mobile.opennet.ru' => 'opennet_main_pda',
	'opennet.ru?news=1' => 'opennet_piece_of_news',
	'ссылка3' => 'действие3',
}

class PluginSkel; end

class OpennetMain_Plugin < PluginSkel
	def work(arg)

	end
end

class OpennetMainWww_Plugin < PluginSkel
	def work(arg)

	end
end

class OpennetMainPda_Plugin < PluginSkel
	def work(arg)
	end
end
