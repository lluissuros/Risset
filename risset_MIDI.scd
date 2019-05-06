//MIDI

(
//NANOKONTROL interface
MIDIIn.connectAll;

//volumes for Nanokontrol:
//TODO move up

MIDIdef.cc(\morphAmp, {arg val;
	var sl = val.linlin(0,127,0,2.0);
	("morph: " + sl).postln;
	Pbindef(\morphFront, \amp, Pseq( [Pexprand(0.1,0.35,1), Pexprand(0.001,0.09,3)],inf) * Pkey(\prob) * sl/2);
}, 0);

MIDIdef.cc(\snaresAmp, {arg val;
	var sl = val.linlin(0,127,0,3.0);
	("snaresRisset: " + sl).postln;
	Pbindef(\rissetSnares, \amp, sl ,inf);
}, 1);

MIDIdef.cc(\buffRissAmp, {arg val;
	var sl = val.linlin(0,127,0,3.0);
	("BufferRisset:" + sl).postln;
	Pbindef(\bufPlayer, \amp, Pseq([0.5, 0.5, 0.8, 0.2] * sl, inf));
}, 2);

MIDIdef.cc(\oneShotAmp, {arg val;
	var sl = val.linlin(0,127,0,3.0);
	("oneShot:" + sl).postln;
	Pbindef(\oneShotBuf,\amp, Prand([0.2] * sl, 1));
}, 3);

MIDIdef.cc(\movingQAmp, {arg val;
	var sl = val.linlin(0,127,0,3.0);
	("movingQAmp:" + sl).postln;
	Pbindef(\movingQFXs,\amp, Prand([0.6,0.9] * sl,inf));
}, 4);


MIDIdef.cc(\rissetFXAmp, {arg val;
	var sl = val.linlin(0,127,0,3.0);
	("rissetFX:" + sl).postln;
	Pbindef(\rissetFXs,\amp, sl/2, inf);
}, 5);


MIDIdef.cc(\returnOutAmp, {arg val;
	var sl = val.linlin(0,127,0,3.0);
	("return Out TODO:" + sl).postln;
	~returnOutAmp.set(val.linexp(0,127,0.1,2.0));
}, 6);


MIDIdef.cc(\masterAmp, {arg val;
	~masterAmp.set(val.linexp(0,127,0.1,2.0));
}, 7);

)