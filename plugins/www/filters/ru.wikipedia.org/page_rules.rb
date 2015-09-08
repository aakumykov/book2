# coding: utf-8

rules = {
	'http://www.opennet.ru/opennews/art.shtml?num=\d+' => 'get_news_with_comments',
	'http://opennet.ru/' => 'two_cols_to_one',
}
