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


	// The main phase indicator. Increases from 0 to 1 in kLen seconds.
	// Reset by a rising edge on resetBus, to the level on posBus.
	// (See below for the reset logic.)
	var phase = Phasor.kr(In.kr(~resetBusIx), so.blockSize/(kLen * s.sampleRate), 0,2, In.kr(~posBusIx.index))
	.poll(1, "phase:");


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
	var gate = In.kr(~gatesRisset, 4);
	var level = In.kr(~levelsRisset, 4);
	var filtWhite = LPF.ar(WhiteNoise.ar(1), 7040, 1);

	Out.ar(0, Pan2.ar(
		Mix(
		// This snare synth is by Esben Stien
			((SinOsc.ar(330,0,0.25) * EnvGen.ar(Env.perc(0.0005,0.055), gate))
				+(SinOsc.ar(185,0,0.25) * EnvGen.ar(Env.perc(0.0005,0.075), gate))
				+(filtWhite * EnvGen.ar(Env.perc(0.0005,0.4), gate) * 0.2)
				+(HPF.ar(filtWhite, 523, 1) * EnvGen.ar(Env.perc(0.0005,0.283), gate) * 0.2)
			) * level
	)));
}).add;
)

Synth(\snareTest);





