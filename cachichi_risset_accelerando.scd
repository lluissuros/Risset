/*


*/

s.boot


(
//TODO: can make it nicer within a Dictionary
//buses
~resetBusIx = Bus.control(s);
~posBusIx = Bus.control(s);
~levelsRisset = Bus.control(s, 4);
~gatesRisset =  Bus.control(s, 4);
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


	// We want to send a reset pulse at the first phrase boundary after the phase hits 1.
	var tock = Delay2.kr(PulseDivider.kr(i, 16, 1));
	Out.kr(~resetBusIx, tock * Integrator.kr(
		phase >= 1,	// When the phase reaches 1, fill up the integrator
		1-Delay1.kr(tock)	// One control cycle after the reset, empty the integrator
	));


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
SynthDef(\snareTest, {
	//uses all risset lines
	var gate = In.kr(~gatesRisset, 4);
	var level = In.kr(~levelsRisset, 4);
	var filtWhite = LPF.ar(WhiteNoise.ar(1), 7040, 1);

	var ampOsc = SinOsc.ar(1/100, pi/2, 0.25, 0.5);


	Out.ar(0, Pan2.ar(
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
a = Synth(\snareTest);
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
SynthDef(\simpleBufPlayerRiss, {
	arg buf=0, rate=1, sPos=0, amp=0.1, out=0, loop=1,
	atk=1.1, sus=0.3, rel=1.1;

	var gate = In.kr(~gatesRisset, 4);
	var level = In.kr(~levelsRisset, 4);

//	var env = EnvGen.kr(Env([0,1,1,0],[atk,sus,rel],[1,0,-1]), gate);
	var env = EnvGen.ar(Env.perc(0.05,0.55), gate);
	var sig = PlayBuf.ar(1, buf, rate*BufRateScale.ir(buf), trigger: gate, startPos:sPos, loop:loop);

	Out.ar(out,
		Pan2.ar(
			Mix(sig * env * level),
			SinOsc.kr(0.05), amp));

}).add;

)





(
b.free;
b = Synth(\simpleBufPlayerRiss, [\buf, ~getRandBuf.(\birds)])
)
b.set(\buf, ~getRandBuf.(\birds));
b.set(\buf, ~getRandBuf.());
b.set(\buf, ~getBufAt.(~niceSoundsESC.choose,\esc50));
b.set(\amp, 0.25);


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

	sig = CombN.ar(sig * env, 1, 10/120, 20);

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
	arg in, out=0, amp=1,atk=0.01, sus=0.3, rel=0.1, pan=0;
	var sigL = In.ar(in,1); //we need to keep stereo so we treat each channel separately
	var sigR = In.ar(in+1,1);

	var gate = In.kr(~gatesRisset, 4);
	var level = In.kr(~levelsRisset, 4);
//	var env = EnvGen.kr(Env([0,1,1,0],[atk,sus,rel],[1,0,-1]), gate);
	var env = EnvGen.ar(Env.perc(atk,rel), gate);

	var sig;
	sigL = Mix(sigL * env * level * amp * 2);
	sigR = Mix(sigR * env * level * amp * 2);
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
	\rel, 0.1
], ~fxGrp);
)









//TODO delete: for inspiration now
(
Pbindef(\movingQESC50,
	\instrument, \substractionMovingQBuf,
//	\buf, Pfunc({~getBufAt.([1050].choose, \esc50)}).stutter(10),
//	\buf, Pfunc({~getRandBuf.(\esc50)}).stutter(10),
	\buf, Pfunc({~getRandBuf.(\birds)}).stutter(1),
	\buf, Pfunc({~getBufAt.(~niceSoundESCLong.choose,\esc50)}).stutter(10),
	\dur, Pseq([3,5,7]/15,inf),
	\loop, 1,
	\release, 1,
	\attack, 3,
	\sustain,5,
	\amp, Pxrand([0.3,0.5,0.7]* 0.25,inf),
	\revMix, Prand([1,0.8,0.5,0.3,0.1],inf),
	\out, Pxrand([2,3,4,5,6,7], inf), //everywhere,
	\pan, Pseq(Array.series(21, -1, 0.1) ,inf),
	\panwidth, 1,
	\rate, Pseq([0].midiratio, inf),
//	\rate, Pseq([2,1,0.5].stutter(4), inf),
	\degree, Pseq([0 ,3, 5, 6, 7]-2,inf),
	\octave, Pseq([2,3,4,5],inf)
);
)


