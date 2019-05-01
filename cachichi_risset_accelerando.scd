/*


*/

s.boot


(
//TODO: can make it nicer within a Dictionary
//buses
~resetBusIx = Bus.control(s);
~resetBusTrigger = Bus.control(s);
~posBusIx = Bus.control(s);
~levelsRisset = Bus.control(s, 4);
~gatesRisset =  Bus.control(s, 4);

// allocate the unique ids for the trigger ids
~idResetTrig = UniqueID.next;
)
(
//TODO: this could be renamed as a Synth, maybe controlsGenerator

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

}.scope(10) // Press 'k' in the scope window to switch between the control signals and the audio
)




(
SynthDef(\snareRissetTest, { |out=0|
	//uses all risset lines
	var gate = In.kr(~gatesRisset, 4);
	var level = In.kr(~levelsRisset, 4);
	var filtWhite = LPF.ar(WhiteNoise.ar(1), 7040, 1);

	var ampOsc = SinOsc.ar(1/100, pi/2, 0.25, 0.5);


	Out.ar(out, Pan2.ar(
		Mix(
		// This snare synth is by Esben Stien
			((SinOsc.ar(330,0,0.25) * EnvGen.ar(Env.perc(0.0005,0.055), gate))
				+(SinOsc.ar(185,0,0.25) * EnvGen.ar(Env.perc(0.0005,0.075), gate))
				+(filtWhite * EnvGen.ar(Env.perc(0.0005,0.4), gate) * 0.2)
				+(HPF.ar(filtWhite, 523, 1) * EnvGen.ar(Env.perc(0.0005,0.283), gate) * 0.2)
			) * level
	),0, ampOsc));
}).add;

)

(
a.free;
a = Synth(\snareRissetTest);
a.set(\out, ~buses[\movingQFX]);
)


(
SynthDef(\sineTest, {
	//uses less risset line
	var gate = In.kr(~gatesRisset, 1);
	var level = In.kr(~levelsRisset, 1);
	var ampOsc = SinOsc.ar(1/100, 0, 0.25, 0.5);

	Out.ar(0, Pan2.ar(
		Mix(
			SinOsc.ar(5000, 0, 0.05)
			* EnvGen.ar(Env.perc(0.05,0.25), gate)
			* level

	),0,ampOsc));
}).add;
)

(
s.free;
s = Synth(\sineTest);
)





(
//interesting sounds
~beats_esc50 = [1084, 2, 630, 411, 611, 1050, 34, 1492];

SynthDef(\simpleBufPlayerRiss, {
	// it loops over and has a long envelope. If sPos changes sounds lees repetittive.
	arg buf=0, out=0, rate=1, sPos=0, amp=0.5, loop=1, pan=0, panWidth=2,
	gated = 0, // 0 means no gate, 1 means gate by risset
	atk=3, sus=8, rel=8;

	var gate = Mix(In.kr(~gatesRisset, 4)).dup * gated;

	var posMover = Line.ar(0, 0.8, atk+sus+rel);
	var framePos = (sPos * BufFrames.kr(buf) + posMover); //adapted to sample

	var sig = PlayBuf.ar(1, buf, rate*BufRateScale.ir(buf), trigger: gate, startPos:framePos, loop:loop);


	//var sig = PlayBuf.ar(1, buf, rate*BufRateScale.ir(buf), startPos:sPos, loop:loop).dup;

	var env = EnvGen.kr(Env.linen(atk, sus, rel, 1, \sin), doneAction:2);

	sig = sig * env * amp;

	//-1 tp +1 to mudlate along the circle
	Out.ar(out, PanAz.ar(2, sig, pan, width: panWidth));
}).add;

)



(
Pbindef(\bufPlayer,
	\instrument, \simpleBufPlayerRiss,
	\buf, Pfunc({~getBufAt.({~beats_esc50.choose}.(),\esc50, true)}).stutter(4),
	\out, ~buses[\rissetFX],
	\dur, Pseq([5,10,15]/8 ,inf),
	\amp, Pseq([0.5, 0.2, 0.8]/8, inf),
	\attack, 1,
	\sustain,1,
	\release, 1,
	\gated, Pwrand([0,1], [4, 1].normalizeSum, inf),
);
Pbindef(\bufPlayer).play;
)

Pbindef(\bufPlayer).play;
Pbindef(\bufPlayer).stop;


Pbindef(\bufPlayer, \out, ~buses[\movingQFX]);
Pbindef(\bufPlayer, \out, ~buses[\infiniteReverbPA]);
Pbindef(\bufPlayer, \out, ~buses[\reverb1PA]);
Pbindef(\bufPlayer, \out, ~buses[\rissetFX]);



Pbindef(\bufPlayer, \buf, ~getBufAt.(630));
Pbindef(\bufPlayer, \buf, ~getRandBuf.(\birds));
Pbindef(\bufPlayer, \buf, Pfunc({~getBufAt.({~beats_esc50.choose}.(),\esc50, true)}).stutter(1));
Pbindef(\bufPlayer, \pan, Pseq(Array.series(21, -1, 0.1) ,inf));
Pbindef(\bufPlayer, \pan, Pseq([1] ,inf));















~buses.keys

(
SynthDef(\logger, {
	var position = In.kr(~posBusIx, 1); //from -0.5 to 0 ()phasor)
	var reset = In.kr(~resetBusIx, 1); // all-time 0 except a 1
	var gate = In.kr(~gatesRisset, 4);  // all-time 0 except some 1
	var level = In.kr(~levelsRisset, 4);  // between 0 and 1

	level.poll;
}).add;
)


(
l.free;
l = Synth(\logger);
)



(
SynthDef(\resetExample, {
	|out=0|
	var reset = In.kr(~resetBusIx, 1); // all-time 0 except a 1
	var env = EnvGen.ar(Env.perc(0.01,0.1), reset);
	var sig = SinOsc.ar(50,0, 0.15);

	//sig = CombN.ar(sig * env, 1, 10/120, 20);
	sig = sig * env;

	Out.ar(out, Pan2.ar(sig));
}).add;
)


(
k.free;
k = Synth(\resetExample);
)




(
SynthDef(\toRissetTest, {
	arg out = 0;
	//test rissetFx
	var sig = SinOsc.ar([440,543]/2, 0,0.125);
	Out.ar(out, sig);
}).add;
)

(
~testFx.free;
~testFx = Synth(\toRissetTest, [\out, ~buses[\rissetFX]]);
)



(
//Takes an audio input and processes it through the risset envelope.
SynthDef(\rissetFX, {
	arg in, out=0, amp=1,atk=0.01, rel=0.1, pan=0;
	var sigL = In.ar(in,1); //we need to keep stereo so we treat each channel separately
	var sigR = In.ar(in+1,1);

	var gate = In.kr(~gatesRisset, 4);
	var level = In.kr(~levelsRisset, 4);
	var env = EnvGen.ar(Env.perc(atk,rel), gate);
	var gainCompensation = 2.5;

	var sig;
	sigL = Mix(sigL * env * level * amp * gainCompensation);
	sigR = Mix(sigR * env * level * amp * gainCompensation);
	sig = [sigL, sigR];

	Out.ar(out, sig);
}).add;
)

(
~rissetFX.free;
~rissetFX = Synth(\rissetFX, [
	\in, ~buses[\rissetFX],
	\out, 0,
	\atk, 0.001,
	\rel, 0.3
], ~fxGrp, \addToHead);
)

~rissetFX.set(\out, ~buses[\reverb1PA])
~rissetFX.set(\out, ~buses[\infiniteReverbPA])
~rissetFX.set(\out, ~buses[\movingQFX])
~rissetFX.set(\rel, 0.4)




(
//substractionMovinqQFx

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
	var compSig =  Compander.ar(sig, sig, thresh: 0.1,slopeBelow: 1, slopeAbove: 0.15, clampTime: 0.01, relaxTime: 0.01,mul:1.5);
	var drySig = compSig * (1-revMix);
	var	wetSig = GVerb.ar(compSig*revMix);

	//TODO SUPEREXPENSIVE: use cheaper reverb, or BETTER route to external reverb
	sig = (drySig + wetSig) * amp * env;

	// -1 to +1 is used to modulate the pan along circle.
	Out.ar(out, PanAz.ar(2, sig, pan) ); //use Mix?
}).add;

)

/*(
~movingQFX.free;
~movingQFX = Synth(\movingQFX, [
	\in, ~buses[\movingQFX],
	\out, 0,
	//\atk, 0.001,
	//\rel, 0.3
], ~fxGrp);
)*/


(
Pbindef(\testMovingQFXs,
	\instrument, \movingQFX,
	\group, ~fxGrp,
	\addAction, \addToTail,
	\in, ~buses[\movingQFX],
	\dur, Pseq([1, 4],inf),
	\atk,  Pseq([9], inf),
	\sus, Pseq([0.1, 1, 9,14], inf),
	\rel, Pseq([9, 1], inf),
	\amp, Prand([0.1,0.2,0.3],inf),
	\revMix, Prand([1,0.8,0.5,0.3,0.1],inf),
	\out, 0, //start for panning
	\pan, Pseq(Array.series(21, -1, 0.1) ,inf),
	\panwidth, 1,
	\degree, Pseq([0 ,3, 5, 6, 7]-2,inf),
	\octave, Pseq([2,4,5,6,7,8,9,10,11],inf)
);
Pbindef(\testMovingQFXs).play;
)















(
SynthDef(\resetExample, {
	|out=0|
	var reset = In.kr(~resetBusIx, 1); // all-time 0 except a 1
	var env = EnvGen.ar(Env.perc(0.01,0.1), reset);
	var sig = SinOsc.ar(50,0, 0.15);

	//sig = CombN.ar(sig * env, 1, 10/120, 20);
	sig = sig * env;

	Out.ar(out, Pan2.ar(sig));
}).add;
)


(
k.free;
k = Synth(\resetExample);
)








//trigger on Reset


/*Simple trigger code...*/
(

SynthDef(\ampListener, {arg id1, limit = 1, thresh = 0.5;
	var src, amp, amptrig, timer;
	src = SoundIn.ar(0);
	// analyze the amplitude input, cause a trigger if the output is over the thresh
	amp = Amplitude.kr(src);
	amptrig = Trig.kr(amp > thresh, limit);
	// use amptrig to see how long it is between triggers.
	//timer = Timer.kr(amptrig);
	// send the values back with two different ids
	SendTrig.kr(amptrig, id1, amp);
	//SendTrig.kr(amptrig, id2, timer);
}).add;


// modulated noise to respond to amp spikes
SynthDef(\makeNoise, {arg freq;
	Out.ar(1, LFNoise1.ar(200) * SinOsc.ar(freq, 0,
		XLine.kr(0.1, 0.00001, 0.5, doneAction: 2)));
}).add;

// allocate the unique ids for the trigger ids
~id1 = UniqueID.next;

// an envelope to poll for amp values later
e = Env([440, 880], [1], \exp);

// add the responder:
o = OSCresponderNode(s.addr, '/tr', {arg time, responder, msg;
	// the msg is an array with 4 values... post them
	msg.postln;
	// the id sent back from the SendTrig is msg[2]... use it to decide what to do
	case
		// amp trigger
		{msg[2] == ~id1}
	   // play a noise burst, higher the amp value, higher the freq(polls the Env 'e')
		{Synth(\makeNoise, [\freq, e[msg[3]]]);
		//change the counter:
		~counterIter = ~counterIter + 1;
	   ~mtranspose.wrapAt(~counterIter).postln;
		~counterPulse = ~counterPulse + 1;
		~mtranspose.wrapAt(~counterPulse).postln;
	}
}).add;

//the listener:
Synth(\ampListener, [\id1, ~idResetTrig, \limit, 0.2, \thresh, 0.75]);

// add a command period function to stop the synths and remove the responder
CmdPeriod.doOnce({
	o.remove; "Removed the responder".postln;
})
)


// register to receive this message
(
~resetTriggerResponder.free;
~resetTriggerResponder = OSCFunc({ arg msg, time;
	//[time, msg].postln;
	case
	{msg[2] == ~idResetTrig}{
		//action:
		Synth(\bufPlayer, [
			\buf, ~findBufferByName.("entryGosh"),
			\atk, 0.001,
			\sus, 2,
			\rel, 4,
			\amp, 0.5,
			\out, ~buses[\infiniteReverbPA]
		])
	}
},'/tr');

)




















