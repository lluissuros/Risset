/*
I'm trying an approach here where:
 * I make use of control buses to send the risset gates
 * I create many instance of FXs with Pbindef, so it is easier to creates atmosferes where Fxs arise in different configurations
 * Right now, routing depends on ~buses object created in Granulizer
 * There is also an option to send to external FXs
 * Ther is some panners for 4channel distibution!
*/





(
// +++++++++++++++++++++++++++++++++++++++++++++++++
// ++    Initialization!!!
// +++++++++++++++++++++++++++++++++++++++++++++++++


//TODO: can make it nicer within a the ~buses Dictionary
//buses
~resetBusIx = Bus.control(s);
~resetBusTrigger = Bus.control(s);
~posBusIx = Bus.control(s);
~levelsRisset = Bus.control(s, 4);
~gatesRisset =  Bus.control(s, 4);

// allocate the unique ids for the trigger ids
~idResetTrig = UniqueID.next;



//TODO: this could be renamed as a Synth, maybe rissetGenerator
{
	//principal parameters
	var kLen = 10; //phasor length
	var kFreq = 8; // ticker frequency
	var kPar = 4; // should be set to the smallest value that sounds right at the chosen frequency

	var s = Server.local; //or Server.internal?
	var so = s.options;


	// The main phase indicator. Increases from 0 to 2 in kLen seconds.
	// Reset by a rising edge on resetBus, to the level on posBus.
	// (See below for the reset logic.)
	var phase = Phasor.kr(In.kr(~resetBusIx), so.blockSize/(kLen * s.sampleRate), 0,2, In.kr(~posBusIx.index));


	// The main ticker. Its frequency rises with the phase, from kFreq to 2*kFreq
	var i = TDuty.kr(1/(kFreq*(1+phase)));

	// We have 5 different "virtual" drum lines. The fastest hits on every tick,
	// the slowest on every 16th tick.
	var pulses = PulseDivider.kr(i, [1,2,4,8,16]);

	// The phase can go slightly below 0 or above 1 just before/after a reset.
	// This can cause strange artefacts if it's used to calc the weight, so clip it.
	var lphase = phase.clip(0,1);

	// The amplitude of the weighted tick represents the number of different virtual drums
	// that are sounding at that time. Also, , as the phase increases from 0 to 1,
	// the fastest drum is faded out and the slowest is faded up, so that the patterns
	// at phase=0 and phase=1 are identical.
	var weightedPulses = ((1-lphase) * pulses[0])
	+ ((pulses@[1,2,3]).sum)
	+ (lphase * pulses[4]);


	var trigger = Trig.kr(phase >= 1, 0.2); //send a reset trigger each time phase hits 1

	// We want to send a reset pulse at the first phrase boundary after the phase hits 1.
	var tock = Delay2.kr(PulseDivider.kr(i, 16, 1));
	Out.kr(~resetBusIx, tock * Integrator.kr(
		phase >= 1,	// When the phase reaches 1, fill up the integrator
		1-Delay1.kr(tock)	// One control cycle after the reset, empty the integrator
	));


	SendTrig.kr(trigger, ~idResetTrig); //send msg back to client


	// The reset position should be such that the frequency is instantaneously halved
	Out.kr(~posBusIx, (phase-1)/2);

	// The drumming is fast enough that the next snare kicks in before the sound of
	// the previous one has faded out, so we need to run several drum synths concurrently.
	// The number that are needed depends on the frequency: it's controlled by the
	// parameter kPar, which should be set to the smallest value that sounds right at the
	// chosen frequency. The drum hits are shared out among the synths, in sequence.

	//we will send both controls to the world:
	(0..(kPar-1)).do({|j|
		Out.kr(~gatesRisset.index + j, PulseDivider.kr(i, kPar, j));
	});
	(0..(kPar-1)).do({|j|
		Out.kr(~levelsRisset.index + j, Latch.kr(weightedPulses / 4,
			In.kr(~gatesRisset.index + j)));
	});

	// Uncomment the next line to get an audible indication of when the reset happens.
	// (Useful for understanding what's happening, and for debugging.)
	//Out.ar(0, SinOsc.ar(220, mul: EnvGen.kr(Env.perc(0.01, 0.1, 0.2), gate: In.kr(~resetBusIx))));

}.scope(10); // Press 'k' in the scope window to switch between the control signals and the audio



SynthDef(\logger, {
	var position = In.kr(~posBusIx, 1); //from -0.5 to 0 ()phasor)
	var reset = In.kr(~resetBusIx, 1); // all-time 0 except a 1
	var gate = In.kr(~gatesRisset, 4);  // all-time 0 except some 1
	var level = In.kr(~levelsRisset, 4);  // between 0 and 1

	level.poll;
}).add;



SynthDef(\snareRisset, { |out=0, atk=1, sus=3, rel=9, amp=0.25, pan=0|
	//uses all risset lines
	var gate = In.kr(~gatesRisset, 4);
	var level = In.kr(~levelsRisset, 4);
	var filtWhite = LPF.ar(WhiteNoise.ar(1), 7040, 1);

	var env = EnvGen.kr(Env.linen(atk, sus, rel, 1, \welch), doneAction:2);


	Out.ar(out, Pan2.ar(
		Mix(
		// This snare synth is by Esben Stien
			((SinOsc.ar(330,0,0.25) * EnvGen.ar(Env.perc(0.0005,0.055), gate))
				+(SinOsc.ar(185,0,0.25) * EnvGen.ar(Env.perc(0.0005,0.075), gate))
				+(filtWhite * EnvGen.ar(Env.perc(0.0005,0.4), gate) * 0.2)
				+(HPF.ar(filtWhite, 523, 1) * EnvGen.ar(Env.perc(0.0005,0.283), gate) * 0.2)
			) * level
	) * env ,pan, amp));
}).add;




//interesting sounds
~beats_esc50 = [1084, 2, 630, 411, 611, 1050, 34, 1492];

SynthDef(\simpleBufPlayerRiss, {
	// it loops over and has a long envelope. If sPos changes sounds lees repetittive.
	arg buf=0, out=0, rate=1, sPos=0, amp=0.5, loop=1, pan=0, panWidth=2,
	gated = 0, // 0 means no gate, 1 means gate by risset
	atk=3, sus=8, rel=8;

	var env = EnvGen.kr(Env.linen(atk, sus, rel, 1, \sin), doneAction:2);
	var gate = Mix(In.kr(~gatesRisset, 4)).dup * gated;
	var posMover = Line.ar(0, 0.6, (atk+sus+rel)/2);
	var framePos = (sPos * BufFrames.kr(buf) + posMover); //adapted to sample
	var sig = PlayBuf.ar(1, buf, rate*BufRateScale.ir(buf), trigger: gate, startPos:framePos, loop:loop);

	sig = sig * env * amp * 0.5;

	Out.ar(out, PanAz.ar(2, sig, pan, width: panWidth)); //-1 to +1 to mudlate along the circle
}).add;



//Takes an audio input and processes it through the risset envelope.
SynthDef(\rissetFX, {
	arg in, out=0, amp=1, pan=0, atk=1, sus=3, rel=9;

	var sigL = In.ar(in,1); //we need to keep stereo so we treat each channel separately
	var sigR = In.ar(in+1,1);

	var gate = In.kr(~gatesRisset, 4);
	var level = In.kr(~levelsRisset, 4);
	var gateEnv = EnvGen.ar(Env.perc(0.01,0.1), gate); //TODO: argument atk
	var gainCompensation = 1;
	var env = EnvGen.kr(Env.linen(atk, sus, rel, 1, \welch), doneAction:2);

	var sig;
	sigL = Mix(sigL * gateEnv * env * level * amp * gainCompensation);
	sigR = Mix(sigR * gateEnv * env * level * amp * gainCompensation);
	sig = [sigL, sigR];

	Out.ar(out, sig);
}).add;



SynthDef(\movingQFX, {
	|in, out=0, freq=1100, amp=0.5, pan=0, revMix=0.2,
	atk=1, sus=3, rel=9|

	var factor =  (10/freq); //keep total rq above zero!
	//freq.poll(Impulse.kr(5));

	//TODO: Check XFade2 for equal power cross fade between two inputs
	//TODO better: this is what I'm doing: { Resonz.ar(WhiteNoise.ar(0.5), 2000, XLine.kr(1, 0.001, 8)) }.play

	var env = EnvGen.kr(Env.linen(atk, sus, rel, 1, \welch), doneAction:2);
	var rq = factor * XLine.kr(100,1,rel)+ LFNoise1.kr(0.1,factor,factor);
	var sig = BPF.ar(In.ar(in,2), freq, rq);
	var compSig =  Compander.ar(sig, sig, thresh: 0.1,slopeBelow: 1, slopeAbove: 0.15, clampTime: 0.01, relaxTime: 0.01,mul:2);
	var drySig = compSig * (1-revMix);
	var	wetSig = GVerb.ar(compSig*revMix);

	//TODO SUPEREXPENSIVE: use cheaper reverb, or BETTER route to external reverb
	sig = (drySig + wetSig) * amp * env;

	// -1 to +1 is used to modulate the pan along circle.
	Out.ar(out, PanAz.ar(2, sig, pan) ); //use Mix?
}).add;


SynthDef(\positionRissetFollowerFX, {
	|in, out=0, ampCorrection=1|
	var sig = In.ar(in, 2);
	var normPosition = (In.kr(~posBusIx, 1) + 0.5) * 2 ; //between 0 and 1
	var ampEnv = LinExp.kr(normPosition, 0, 1, 0.1, 1.2); //better exp for amplitudes
	ampEnv = Lag.kr(ampEnv);
//	ampEnv.poll;

	Out.ar(out, sig * ampEnv *  ampCorrection);
}).add;


SynthDef(\extSend1, {
	|in, out|
	var sig = In.ar(in,2);
	Out.ar(out, sig);
}).add;

SynthDef(\extReturn1,{
	|in, out|
	var sig = SoundIn.ar([in, in+1]);
	Out.ar(out, sig);
}).add;


//SPATIALIZING: takes an input and spreads it around
SynthDef(\surroundCircle4,{
	|in, out=0, circleFreq=10, amp=0,
	atk=8, sus=8, rel=8|
	var inL = In.ar(in, 1) * amp;
	var inR = In.ar(in+1, 1) * amp;
	var env = EnvGen.kr(Env.linen(atk, sus, rel, 1, \sin), doneAction:2);

	Out.ar(out, PanAz.ar(4, inL*env, LFSaw.ar(circleFreq)));
	Out.ar(out, PanAz.ar(4, inR*env, LFSaw.ar(circleFreq)));
}).add;


//Takes input and Grains it like panAz
SynthDef(\grainPanAzFX, {
	|in, out=0, grainFreq=250, grainDur=0.1, pan=0,
	atk=8, sus=8, rel=8, amp=0.5|
	var inL = In.ar(in, 1);
	var inR = In.ar(in+1, 1);
	var grainedL = GrainIn.ar(4, Dust.kr(grainFreq), grainDur, inL, pan);
	var grainedR = GrainIn.ar(4, Dust.kr(grainFreq), grainDur, inR, pan);
	var env = EnvGen.kr(Env.linen(atk, sus, rel, 1, \sin), doneAction:2);
	Out.ar(out, grainedL * env * amp);
	Out.ar(out, grainedR * env * amp);
}).add;

"All synhtDefs created!".postln;



//The Pbindefs
Pbindef(\rissetSnares,
	\instrument, \snareRisset,
	\out, Pwrand([
		~buses[\reverb1PA],  ~buses[\infiniteReverbPA], ~buses[\movingQFX], ~buses[\externalSend1]], [2,1,2,1].normalizeSum, inf),
	\dur, Pseq([25],inf),
	\atk, Pseq([5], inf),
	\sus, Pseq([5], inf),
	\rel, Pseq([5], inf),
	\amp, Prand([0.25],inf),
	\pan, 0,
);

Pbindef(\bufPlayer,
	\instrument, \simpleBufPlayerRiss,
	\buf, Pfunc({~getBufAt.({~beats_esc50.choose}.(),\esc50, true)}).stutter(4),
	\out, ~buses[\rissetFX],
	\dur, Pseq([5,10,15] ,inf),
	\amp, Pseq([0.5, 0.2, 0.8]/15, inf),
	\atk, 1,
	\sus,8,
	\rel, 8,
	//\gated, Pwrand([0,1], [4, 1].normalizeSum, inf),
	\gated, 1,
);


Pbindef(\rissetFXs,
	\instrument, \rissetFX,
	\group, ~fxGrp,
	\addAction, \addToHead,
	\in, ~buses[\rissetFX],
	\out, ~buses[\movingQFX],
	\dur, Pseq([5],inf),
	\atk, Pseq([3], inf),
	\sus, Pseq([4], inf),
	\rel, Pseq([3], inf),
	\amp, Prand([0.5],inf),
);


Pbindef(\movingQFXs,
	\instrument, \movingQFX,
	\group, ~fxGrp,
	\addAction, \addToTail,
	\in, ~buses[\movingQFX],
	\dur, Pseq([1, 4],inf),
	\atk,  Pseq([9], inf),
	\sus, Pseq([0.1, 1, 9,14], inf),
	\rel, Pseq([9, 1], inf),
	\amp, Prand([0.6,0.9],inf),
	\revMix, Prand([1,0.8,0.5,0.3,0.1],inf),
	\out, ~buses[\reverb1PA],
	\pan, Pseq(Array.series(21, -1, 0.1) ,inf),
	\panwidth, 1,
	\degree, Pseq([0 ,3, 5, 6, 7]-2,inf),
	\octave, Pseq([2,4,5,6,7,8,9,10,11].mirror,inf)
);


Pbindef(\oneShotBuf,
	\instrument, \simpleBufPlayerRiss,
	\buf, ~findBufferByName.("entryGosh"),
	\atk, 1,
	\sus, 2,
	\rel, 2,
	\gated, 0,
	\loop, 0,
	\amp, Prand([0, 0.01, 0.05, 0.1], 1),
	\out, Prand([~buses[\infiniteReverbPA], ~buses[\movingQFX]]),
);


Pbindef(\grainPanFxs,
	\instrument, \grainPanAzFX,
	\group, ~spatializersGrp,
	\addAction, \addToTail,
	\in, ~buses[\grainPan],
	\out, 0,
	\atk, 0.1,
	\sus, 0.1,
	\rel, 0.1,
	\dur, Pseq([0.1], inf),
	\pan, Pbrown(-1.0,1.0, 0.05, inf),
);


Pbindef(\surroundCircle4,
	\instrument, \surroundCircle4,
	\group, ~spatializersGrp,
	\addAction, \addToTail,
	\in, ~buses[\panAzCircle],
	\out, 0,
	\dur, Pseq([2], inf),
	\atk, 1.5,
	\sus, 1.5,
	\rel, 1.5,
	\circleFreq, Pbrown(1,10,0.05, inf),
);


"All Pbindefs created".postln;


//TODO: sometime gives error!!
//send to pedals and return
if(~send1ToPedals.isNil){}{~send1ToPedals.free};
~send1ToPedals = Synth(\extSend1, [
	\in, ~buses[\externalSend1],
	\out, 4,
], ~externalGrp);


if(~return1.isNil){}{~return1.free};
~return1 = Synth(\extReturn1, [
	\in, 2,
	\out, ~buses[\reverb1PA],
], ~externalGrp, \addToTail);



// postion follower FX
if(~positionFollower.isNil){}{~positionFollower.free};
~positionFollower = Synth(\positionRissetFollowerFX, [
	\in, ~buses[\positionRissetFollowerFX],
	\out, ~buses[\externalSend1]
], ~fxGrp);

"Singleton Fxs created".postln;



Pbindef(\rissetFXs).play;
Pbindef(\movingQFXs).play;
Pbindef(\grainPanFxs).play;
Pbindef(\surroundCircle4).play;

"some FXs are already runnig :)".postln;
s.plotTree;

)








//risset snares
Pbindef(\rissetSnares).play;

Pbindef(\rissetSnares, \out, Pwrand([
	~buses[\reverb1PA],  ~buses[\infiniteReverbPA], ~buses[\movingQFX], ~buses[\externalSend1]],
[2,1,2,1].normalizeSum, inf));



//play buffers
Pbindef(\bufPlayer).play;
Pbindef(\bufPlayer).stop;

Pbindef(\bufPlayer, \out, ~buses[\movingQFX]);
Pbindef(\bufPlayer, \out, ~buses[\infiniteReverbPA]);
Pbindef(\bufPlayer, \out, ~buses[\reverb1PA]);
Pbindef(\bufPlayer, \out, ~buses[\rissetFX]);
Pbindef(\bufPlayer, \out, ~buses[\positionRissetFollowerFX]);

Pbindef(\bufPlayer, \buf, ~getBufAt.(630));
Pbindef(\bufPlayer, \buf, ~getRandBuf.(\birds));
Pbindef(\bufPlayer, \buf, Pfunc({~getBufAt.({~beats_esc50.choose}.(),\esc50, true)}).stutter(1));
Pbindef(\bufPlayer, \pan, Pseq(Array.series(21, -1, 0.1) ,inf));
Pbindef(\bufPlayer, \pan, Pseq([1] ,inf));

Pbindef(\bufPlayer, \amp, Pseq([0.5] ,inf));



//the risset!
Pbindef(\rissetFXs).play;
Pbindef(\rissetFXs).stop;

Pbindef(\rissetFXs, \out, Pwrand([
	~buses[\reverb1PA],  ~buses[\infiniteReverbPA], ~buses[\movingQFX], ~buses[\externalSend1]],
[2,1,2,1].normalizeSum, inf)
);

Pbindef(\rissetFXs, \amp, Pseq([0.5, 1, 0.7], inf));
Pbindef(\rissetFXs, \dur, Pseq([5, 1, 2]/2, inf));



//MovingQs
Pbindef(\movingQFXs).play;

Pbindef(\movingQFXs,\out, Pwrand([~buses[\reverb1PA], ~buses[\infiniteReverbPA], ~buses[\externalSend1]], [2,1,1].normalizeSum, inf));

Pbindef(\movingQFXs, \pan, 1)
Pbindef(\movingQFXs, \out, 0)

//trigger on Reset
(
if(~resetTriggerResponder.isNil){}{~resetTriggerResponder.free};
~resetTriggerResponder = OSCFunc({ arg msg, time;
	//[time, msg].postln;
	case
	{msg[2] == ~idResetTrig}{
		Pbindef(\oneShotBuf).play;
	}
},'/tr');
)
(
Pbindef(\oneShotBuf,
	\instrument, \simpleBufPlayer,
	\buf, ~findBufferByName.("entryGosh"),
	\atk, 1,
	\sus, 2,
	\rel, 2,
	\amp, Prand([0, 0.01, 0.05, 0.1], 1),
	\out, Prand([~buses[\infiniteReverbPA], ~buses[\movingQFX]]),
));
//only one shot so Pseq will always give the first!
Pbindef(\oneShotBuf, \out, Prand([~buses[\infiniteReverbPA]]));
Pbindef(\oneShotBuf, \out, Prand([~buses[\movingQFX]]));
Pbindef(\oneShotBuf, \out, Prand([~buses[\infiniteReverbPA], ~buses[\movingQFX]]));
Pbindef(\oneShotBuf, \amp, Prand([0.1], 1));
Pbindef(\oneShotBuf, \buf, Prand([ ~findBufferByName.("entryGosh"), ~findBufferByName.("shakerSustain")]));





//position follower
~positionFollower.set(\out, ~buses[\movingQFX]);
~positionFollower.set(\out, ~buses[\rissetFX]);
~positionFollower.set(\out, ~buses[\infiniteReverbPA]);
~positionFollower.set(\out, ~buses[\reverb1PA]);
~positionFollower.set(\out, ~buses[\grainPan]);
~positionFollower.set(\out, ~buses[\externalSend1]);
\reverb1PA


~buses.keys
-> Set[ reverb0PA, rissetFX, reverb1Vib, stresonVib, stresonSurr, panAzCircle, positionRissetFollowerFX, infiniteReverbPA, reverb0Vib, reverb0Surr, infiniteReverbVib, infiniteReverbSurr, stresonPA, reverb1PA, reverb1Surr, grainPan, movingQFX, externalSend1 ]



//SPATIALIZING

//Do it as pbind!!!
Pbindef(\grainPanFxs).play;
Pbindef(\surroundCircle4).play;

Pbindef(\surroundCircle4).play;
Pbindef(\grainPanFxs).stop;






// +++++++++++++++++++++++++++++++++++++++++++++++
// ++   PERFORMANCE CACHICI:
// +++++++++++++++++++++++++++++++++++++++++++++++

(
//morphFront
Pbindef(\morphFront,  \out, ~buses[\positionRissetFollowerFX]).play;
Pbindef(\morphFront).play;
Pbindef(\morphFront, \sPos, Pdefn(\incrementally_0_to_1_millis_and_back).stutter(1));
)

Pbindef(\morphFront).stop;


//presets!
~callPreset.(1)
~callPreset.(2)
~callPreset.(3)
~callPreset.(4)
~callPreset.(5)
~callPreset.(6)
~callPreset.(7)
~callPreset.(8)

~logActiveSounds.();
~probCycleDurSeconds = 0.1



// 2- reset
(
if(~resetTriggerResponder.isNil){}{~resetTriggerResponder.free};
~resetTriggerResponder = OSCFunc({ arg msg, time;
	//[time, msg].postln;
	case
	{msg[2] == ~idResetTrig}{
		Pbindef(\oneShotBuf).play;
	}
},'/tr');
)
Pbindef(\oneShotBuf, \out, Prand([~buses[\infiniteReverbPA], ~buses[\movingQFX]]));





