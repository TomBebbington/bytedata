using sys.io.File;
using sys.FileSystem;
typedef UInt = Int;
enum HairColour {
	Black;
	DarkBrown;
	Brown;
	Blonde;
	Grey;
	Ginger;
}
class Identity extends data.Data {
	@:len(2) var magic:Int = 0x4944;
	@:len(1) var nameLen:UInt;
	@:len(nameLen) public var name:String;
	public var birth:Date; // length not needed, implied by Date to be 64-bit
	@:len(2) var interestsLen:Int;
	@:len(interestsLen) public var interests:Array<String>;
	@:len(1) public var rating:Int;
	public var hair:HairColour;
	static function concat(a:Array<String>):String {
		return switch(a) {
			case [v]: v;
			case [a, b]: '$a and $b';
			default: a[0] + ", " + concat(a.slice(1));
		}
	}
	public function toString():String {
		return '$name - $rating: ${Date.now().getFullYear() - birth.getFullYear()} years old and interested in ${concat(interests)}';
	}
}
class Test {
	static var FILENAME = "tests/rick.id";
	public static function main() {
		if(FILENAME.exists()) {
			var i = new Identity();
			i.read(FILENAME.read(true));
			trace(i);
		} else {
			var i = new Identity();
			i.name = "Rick Grimes";
			i.birth = new Date(1976, 9, 1, 11, 10, 4);
			i.interests = ["Things", "Stuff", "Walkers gotta die", "Goshdangit Carl", "Noooo Shane"];
			i.rating = 99;
			i.write(FILENAME.write(true));
		}
	}
}