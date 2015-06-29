<?php
//header("Content-Type: text/html; charset=UTF-8",true);
////include_once('../eBookCreator/debug.php');
////include_once('../eBookCreator/exception.php');

class Ncx extends Debug
{	
	protected $depth = 0;
	protected $totalPageCount = 0;
	protected $maxPageNumber = 0;
		
	function __construct()
	{
		$this->debug(__METHOD__);
	}
	
	function makeNavPoint($tocArray)
	{
		$this->debug(__METHOD__);
		
		$data = "";
		
		foreach($tocArray as $item)
		{
			$id = md5($item['title']);
			$playOrder = $item['id'];
			
			$data .= <<<NAVPOINT

	<navPoint id='{$id}' playOrder='{$playOrder}'>
		<navLabel><text>{$item['title']}</text></navLabel>
		<content src='{$item['file']}'/>
NAVPOINT;
			
			if( isset($item['subitems']) && !empty($item['subitems'])) $data .= $this->makeNavPoint($item['subitems']);
			
			$data .= "\n\t</navPoint>";
		}
		
		return $data;
	}
	
	function generate($metadata,$tocArray)
	{
		$this->debug(__METHOD__);
		
		$navPoints = $this->makeNavPoint($tocArray);
		
		$ncx = <<<NCX
<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
<ncx version="2005-1" xmlns="http://www.daisy.org/z3986/2005/ncx/">
<head>
	<meta content="FB2BookID" name="dtb:uid"/>
	<meta content="1" name="dtb:{$this->depth}"/>
	<meta content="0" name="dtb:{$this->totalPageCount}"/>
	<meta content="0" name="dtb:{$this->maxPageNumber}"/>
</head>
<docTitle>
	<text>{$metadata['title']}</text>
</docTitle>
<navMap>{$navPoints}
</navMap>
</ncx>
NCX;
		
		return $ncx;
	}
	
}


//$tocArray = unserialize( file_get_contents("eBookCreator/tocArray.txt") );
//pre($tocArray);

//$ncx = new Ncx(array('title'=>'opennet.ru'),$tocArray);
//$ncxData = $ncx->generate();
//pre($ncxData);
