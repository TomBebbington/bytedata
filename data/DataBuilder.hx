package data;
using Lambda;
import haxe.macro.Expr;
import haxe.macro.Type;
using haxe.macro.Context;
using haxe.macro.ComplexTypeTools;
class DataBuilder {
	public var dataFields:Array<Field>;
	public var fields:Array<Field>;
	public var bigEndian:Bool;
	public function new(fs:Array<Field>) {
		bigEndian = !(Context.getLocalClass().get().meta.has(":littleEndian"));
		fields = fs.copy();
		dataFields = [for(f in fs) if(f.kind.getName() == "FVar" && !f.access.has(Access.AStatic)) f];
		for(f in dataFields) {
			var l = getLen(f);
			var fref:Expr = {expr: EConst(CIdent(f.name)), pos: f.pos};
			if(l != null)
				switch(l.expr) {
					case EConst(CIdent(s)):
						for(of in dataFields)
							if(of.name == s) {
								var ftype = null, fexpr = null;
								switch(of.kind) {
									case FieldType.FVar(t, e):
										ftype = t;
										fexpr = e;
									default: null;
								}
								of.kind = FieldType.FProp("get", "never", macro:Int);
								fields.push({
									access: of.access.concat([AInline]),
									pos: of.pos,
									name: 'get_${of.name}',
									kind: FieldType.FFun({
										expr: macro return $fref.length,
										ret: macro:Int,
										params: [],
										args: []
									})
								});
							}
					default: 
				}
		}
		fields.push(readField());
		fields.push(writeField());
		for(f in fields) trace(new haxe.macro.Printer().printField(f));
	}
	static function getLen(f:Field):ExprOf<Int> {
		var len:Expr = null;
		for(e in f.meta) if(e.name == ":len") len = e.params[0];
		return len;
	}
	function genWriteField(f:Field):Expr {
		var len = getLen(f);
		var old:Expr = { expr: EConst(CIdent(f.name)), pos: f.pos};
		function genType(t:ComplexType, v, ?len) {
			var lenc:Int = len == null ? 0 : resolveConstant(len);
			var tt:Type = try Context.getType(t.toString()) catch(e:Dynamic) null;
			return switch(t) {
				case TPath({name: "Int"}) if(lenc == 1): macro o.writeInt8($v);
				case TPath({name: "Int"}) if(lenc == 2): macro o.writeInt16($v);
				case TPath({name: "Int"}) if(lenc == 3): macro o.writeInt24($v);
				case TPath({name: "Int"}) if(lenc == null || lenc == 4): macro o.writeInt32($v);
				case TPath({name: "Int"}): macro switch($len) {
					case 1: o.writeInt8($v);
					case 2: o.writeInt16($v);
					case 3: o.writeInt24($v);
					case 4: o.writeInt32($v);
					case all: throw "Unsupported int of length "+all;
				}
				case TPath({name: "UInt"}) if(lenc == 1): macro o.writeByte($v);
				case TPath({name: "UInt"}) if(lenc == 2): macro o.writeUInt16($v);
				case TPath({name: "UInt"}) if(lenc == 3): macro o.writeUInt24($v);
				case TPath({name: "String"}) if(len == null): macro { o.writeUInt16($v.length); o.writeString($v); };
				case TPath({name: "String"}): macro o.writeString($v);
				case TPath({name: "Float"}) if(lenc == 32): macro o.writeFloat($v);
				case TPath({name: "Single"}): macro o.writeFloat($v);
				case TPath({name: "Float"}): macro o.writeDouble($v);
				case TPath({name: "Int64"}): macro o.writeInt64($v);
				case TPath({name: "Date"}): macro o.writeDouble($v.getTime());
				case TPath({name: "Bytes"}): macro o.write($v);
				case TPath({name: "Array", params: [TPType(p)]}): var gd = genType(p, macro it, null); macro for(it in $v) $gd;
				case TPath({name: "Vector", params: [TPType(p)]}) if(len != null):
					var gd = genType(p, macro i);
					macro for(i in $v) $gd;
				case all: switch(tt) {
					case TEnum(typ, []):
						macro i.writeUInt16(Type.enumIndex($v));
					default: throw 'Cannot write type ${all.toString()}/$all';
				}
			}
		}
		var expr = switch(f.kind) {
			case FieldType.FVar(t, e) if(e != null):
				genType(t, e, len);
			case FieldType.FVar(t, _):
				genType(t, old, len);
			case FieldType.FProp(_, _, t, _):
				genType(t, old, len);
			default: null;
		}
		return expr;
	}
	function genReadField(f:Field):Expr {
		var olen = getLen(f);
		var accessor:Expr = { expr: EConst(CIdent(f.name)), pos: f.pos};
		function readType(t:ComplexType, ?len) {
			var lenc:Int = len == null ? 0 : resolveConstant(len);
			var tt:Type = try Context.getType(t.toString()) catch(e:Dynamic) null;
			return switch(t) {
				case TPath({name: "Int"}) if(lenc == 1): macro i.readInt8();
				case TPath({name: "Int"}) if(lenc == 2): macro i.readInt16();
				case TPath({name: "Int"}) if(lenc == 3): macro i.readInt24();
				case TPath({name: "Int"}) if(lenc == 4 || len == null): macro i.readInt32();
				case TPath({name: "Int"}) if(len != null): macro switch($len) {
					case 1: i.readInt8();
					case 2: i.readInt16();
					case 3: i.readInt24();
					case 4: i.readInt32();
					case all: throw "Unsupported int of length "+all;
				}
				case TPath({name: "UInt"}) if(lenc == 1): macro i.readByte();
				case TPath({name: "UInt"}) if(lenc == 2): macro i.readUInt16();
				case TPath({name: "UInt"}) if(lenc == 3): macro i.readUInt24();
				case TPath({name: "UInt"}) if(len != null): macro switch($len) {
					case 1: i.readByte();
					case 2: i.readUInt16();
					case 3: i.readUInt24();
					case all: throw "No support for uint with size "+all;
				}
				case TPath({name: "Int"}):  macro i.readInt32();
				case TPath({name: "String"}) if(len == null): macro {var l = i.readUInt16(); i.readString(l);};
				case TPath({name: "String"}): macro i.readString($len);
				case TPath({name: "Float"}) if(lenc == 32): macro i.readFloat();
				case TPath({name: "Single"}): macro i.readFloat();
				case TPath({name: "Float"}): macro i.readDouble();
				case TPath({name: "Int64"}): macro i.readInt64();
				case TPath({name: "Date"}): macro Date.fromTime(i.readDouble());
				case TPath({name: "Bytes"}) if(len == null): throw 'Length required for Bytes \'${f.name}\'';
				case TPath({name: "Bytes"}) if(len != null): macro i.read($len);
				case TPath({name: "Array", params: [TPType(p)]}) if(len != null):
					var re = readType(p, null);
					macro [for(_ in 0...$len) $re];
				case TPath({name: "Vector", params: [TPType(p)]}) if(len != null):
					var re = readType(p, null);
					macro {
						var v = new haxe.ds.Vector($len);
						for(n in 0...$len) v[n] = $re;
						v;
					}
				case all: switch(tt) {
					case TEnum(typ, []):
						//var et = typ.get();
						macro Type.createEnumIndex(macro $all, i.readUInt16());
					default: throw 'Cannot read type ${all.toString()}/$all';
				}
			}
		}
		return switch(f.kind) {
			case FieldType.FVar(t, e) if(e != null):
				var ve = readType(t, olen);
				macro if($ve != $e) throw "Invalid data";
			case FieldType.FVar(t, _):
				var ve = readType(t, olen);
				macro $accessor = $ve;
			case FieldType.FProp(_, _, t, _):
				var ve = readType(t, olen);
				var name = f.name;
				macro var $name:Int = $ve;
			default: null;
		}
	}
	function resolveConstant(e:Expr):Dynamic {
		return switch(e.expr) {
			case EConst(CInt(v)): Std.parseInt(v);
			case EConst(CFloat(f)): Std.parseFloat(f);
			case EConst(CString(s)): s;
			case EConst(CIdent("true")): true;
			case EConst(CIdent("false")): false;
			default: null;
		}
	}
	public function readField():Field {
		var fblock = [macro i.bigEndian = $v{bigEndian}];
		for(d in dataFields) {
			var f = genReadField(d);
			if(f != null)
				fblock.push(f);
		}
		fblock.push(macro i.close());
		var fexpr = {expr: ExprDef.EBlock(fblock), pos: Context.currentPos()};
		return {
			access: [APublic, AOverride],
			pos: Context.currentPos(),
			name: "read",
			kind: FieldType.FFun({
				ret: macro:Void,
				params: [],
				args: [{
					type: macro: haxe.io.Input,
					opt: false,
					name: "i"
				}],
				expr: fexpr
			})
		};
	}
	public function writeField():Field {
		var fblock = [macro o.bigEndian = $v{bigEndian}];
		for(d in dataFields)
			switch(d.kind) {
				case FVar(_, _) | FProp(_, _, _, _): fblock.push(genWriteField(d));
				default:
			}
		fblock.push(macro o.close());
		var fexpr = {expr: ExprDef.EBlock(fblock), pos: Context.currentPos()};
		return {
			access: [APublic, AOverride],
			pos: Context.currentPos(),
			name: "write",
			kind: FieldType.FFun({
				ret: macro:Void,
				params: [],
				args: [{
					type: macro: haxe.io.Output,
					opt: false,
					name: "o"
				}],
				expr: fexpr
			})
		};
	}
	public static macro function build():Array<Field> {
		return new DataBuilder(Context.getBuildFields()).fields;
	}
}