//
//  DesktopPetView.swift
//  Mona
//
//  Created by Codex on 2026/7/26.
//

import Combine
import SwiftUI

struct DesktopPetView: View {
    let regions: PetInteractionRegions
    let touch: PetTouchState
    let machine: MachineStatusMonitor
    var openSettings: () -> Void
    var toggleVisibility: () -> Void
    var quit: () -> Void

    @AppStorage(PetPreferences.showsCodexUsageKey) private var showsCodexUsage = true
    @AppStorage(PetPreferences.showsClaudeUsageKey) private var showsClaudeUsage = true
    @AppStorage(PetPreferences.showsMachineStatusKey) private var showsMachineStatus = true

    @State private var isBreathing = false
    @State private var blinkImageName: String?
    @State private var blinkSequence = 0
    @State private var dialogueMouthImageName: String?
    @State private var dialogueMouthSequence = 0
    @State private var shakeDegrees: Double = 0
    @State private var shakeSequence = 0
    @State private var annoyance = PetAnnoyance()
    @State private var lastCasualLine: String?
    @State private var currentVoice: PetVoice?
    @State private var stageHoldUntil: Date?
    @State private var lastStrokeLine: String?
    @State private var lastSpontaneousLine: String?
    @State private var lastStrokeRemarkAt: Date?
    @State private var afterglowImageName: String?
    @State private var afterglowSequence = 0
    @State private var lastInteraction = Date()
    /// When *you* last handled him, as opposed to anything happening at all. He
    /// dozes off on this one, so talking in his sleep does not count as waking.
    @State private var lastTouchedAt = Date()
    @State private var isAsleep = false
    @State private var dozeImageName: String?
    @State private var dozeSequence = 0
    @State private var isShowingSleepZs = false
    @State private var meowEffectSequence = 0
    @State private var isShowingMeowEffect = false
    @State private var meowEffectScale = 0.2
    @State private var meowEffectOpacity = 0.0
    @State private var meowEffectRise = 38.0
    @State private var nextBlinkAt = Date().addingTimeInterval(2)
    @State private var isDialogueVisible = false
    @State private var dialogueText = ""
    @State private var petExpression: PetExpression = .regular
    @State private var dialoguePages: [DialoguePage] = []
    @State private var dialoguePageIndex = 0
    @State private var lastDialogueInteraction: Date?
    // Reserved for future automatically advancing dialogue sequences.
    @State private var isDialogueAutoPlaying = false

    @State private var nightWatch = PetNightWatch(spokenSlot: PetQuietHours.nightSpokenSlot)
    @State private var hourChime = PetHourChime(lastChimedHour: PetQuietHours.lastChimedHour)
    /// Shared by both, so the chime and the nagging cannot land on top of one
    /// another.
    @State private var lastSpontaneousAt: Date? = PetQuietHours.lastSpontaneousAt

    private let idleTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.clear

            HStack(alignment: .bottom, spacing: -20) {
                VStack(spacing: 2) {
                    PetSprite(
                        imageName: spriteImageName,
                        isBreathing: isBreathing,
                        shakeDegrees: shakeDegrees,
                        leanDegrees: touch.strokeLean
                    )
                    .frame(width: PetLayout.spriteSize.width, height: PetLayout.spriteSize.height)
                    .overlay(alignment: .topTrailing) {
                        ZStack(alignment: .topTrailing) {
                            if isShowingSleepZs {
                                SleepingZs()
                                    .padding(.trailing, 20)
                                    .padding(.top, 26)
                                    .transition(.opacity)
                            }

                            if isShowingMeowEffect {
                                Image("miaowu")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 72, height: 108)
                                    .scaleEffect(meowEffectScale, anchor: .bottomLeading)
                                    .opacity(meowEffectOpacity)
                                    .offset(x: 15, y: -18 + meowEffectRise)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(PetLayout.rootSpace))
                    } action: { frame in
                        regions.setSpriteFrame(frame)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        interact()
                    }
                    .contextMenu {
                        if showsCodexUsage {
                            Button("查看 Codex 用量") {
                                startUsageDialogue()
                            }
                        }
                        if showsClaudeUsage {
                            Button("查看 Claude 额度") {
                                present(ClaudeUsageReader.latestDialogue(), as: .quota)
                            }
                        }
                        if showsMachineStatus {
                            Button("查看本机状态") {
                                present(
                                    MachineStatusReport.pages(for: machine.current()),
                                    as: .machineStatus
                                )
                            }
                        }
                        if showsCodexUsage || showsClaudeUsage || showsMachineStatus {
                            Divider()
                        }
                        Button("设置…") {
                            openSettings()
                        }
                        Button("隐藏") {
                            toggleVisibility()
                        }
                        Divider()
                        Button("退出") {
                            quit()
                        }
                    }
                }

                if isDialogueVisible {
                    PersonaDialogueBox(
                        message: dialogueText
                    )
                    .frame(
                        width: PetLayout.dialogueSize.width,
                        height: PetLayout.dialogueSize.height
                    )
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(PetLayout.rootSpace))
                    } action: { frame in
                        regions.setDialogueFrame(frame)
                    }
                    .padding(.bottom, PetLayout.dialogueBottomPadding)
                    .onTapGesture {
                        interactWithDialogue()
                    }
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.88, anchor: .bottomLeading)
                                .combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                } else {
                    Spacer()
                        .frame(width: PetLayout.dialogueSize.width)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(width: PetLayout.windowSize.width, height: PetLayout.windowSize.height)
        .coordinateSpace(.named(PetLayout.rootSpace))
        .onAppear {
            isBreathing = true
        }
        .onChange(of: spriteImageName, initial: true) {
            regions.setSpriteImageName(spriteImageName)
        }
        .onChange(of: isDialogueVisible, initial: true) {
            regions.setDialogueVisible(isDialogueVisible)
        }
        .onChange(of: touch.strokedZone) { previous, current in
            handleStrokeChange(from: previous, to: current)
        }
        .onReceive(idleTimer) { now in
            updateSleep(at: now)
            triggerBlinkIfNeeded(at: now)
            hideDialogueIfTimedOut(at: now)
            considerSpeakingUp(at: now)
        }
    }

    /// Resolved here rather than inside `PetSprite` so the hit tester and the
    /// screen always agree on which frame is showing.
    private var spriteImageName: String {
        if let dialogueMouthImageName {
            return dialogueMouthImageName
        }
        if let expression = touch.strokedZone?.strokeExpression {
            return expression.rawValue
        }
        if let dozeImageName {
            return dozeImageName
        }
        if isAsleep {
            return PetExpression.sleep.rawValue
        }
        if let afterglowImageName {
            return afterglowImageName
        }
        if let blinkImageName, petExpression == .regular {
            return blinkImageName
        }
        return petExpression.rawValue
    }

    private func showMeowEffect() {
        meowEffectSequence += 1
        let sequence = meowEffectSequence

        isShowingMeowEffect = false
        meowEffectScale = 0.2
        meowEffectOpacity = 0
        meowEffectRise = 38

        DispatchQueue.main.async {
            guard sequence == meowEffectSequence else { return }
            isShowingMeowEffect = true
            withAnimation(.spring(response: 0.51, dampingFraction: 0.68)) {
                meowEffectScale = 1
                meowEffectOpacity = 1
                meowEffectRise = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.74) {
            guard sequence == meowEffectSequence else { return }
            withAnimation(.easeIn(duration: 0.24)) {
                meowEffectScale = 0.82
                meowEffectOpacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.01) {
            guard sequence == meowEffectSequence else { return }
            isShowingMeowEffect = false
        }
    }

    private func handleStrokeChange(from previous: PetTouchZone?, to current: PetTouchZone?) {
        let now = Date()

        if let current {
            lastInteraction = now
            lastTouchedAt = now
            cancelBlink()

            if previous == nil {
                remarkOnStroke(in: current, at: now)
            }
            return
        }

        // Hand lifted. Sparkle-eyed for a moment is the payoff for the squint.
        if previous == .head {
            startAfterglow()
        }
    }

    private func remarkOnStroke(in zone: PetTouchZone, at time: Date) {
        if let lastStrokeRemarkAt,
           time.timeIntervalSince(lastStrokeRemarkAt) < PetTouchTuning.remarkCooldown {
            meowIfBecoming(zone)
            return
        }
        guard let page = PetStrokeDialogue.page(for: zone, avoiding: lastStrokeLine) else {
            meowIfBecoming(zone)
            return
        }

        // Only spend the cooldown if he actually got to say it; `.stroke` waits
        // for silence, so this is often turned down.
        guard present([page], as: .stroke) else {
            // Turned down because something is already on screen — and the effect
            // would land across the dialogue box's left edge, so it stays in.
            return
        }
        lastStrokeLine = page.message
        lastStrokeRemarkAt = time
    }

    /// The sound and the face that goes with it.
    ///
    /// Always `smile`, which is also what having his head rubbed puts him in —
    /// so the mouth frames outranking the stroke expression in `spriteImageName`
    /// no longer matters. They agree, and a stroke that draws a meow now moves
    /// his mouth for it instead of leaving the face still.
    ///
    /// Reverting is left to the animation's completion, which only runs while the
    /// sequence still matches: a line arriving mid-meow takes the mouth over and
    /// this quietly stops rather than clearing someone else's expression.
    private func meow() {
        showMeowEffect()

        guard !isDialogueVisible, !isAsleep else { return }
        petExpression = .smile
        cancelBlink()
        startMouthAnimation(for: .smile) {
            dialogueMouthImageName = nil
            petExpression = .regular
        }
    }

    /// A sound instead of a sentence, for the strokes that pass without one.
    ///
    /// Only where it would not contradict his face. Belly and feet put him in
    /// `angry` — being handled there is an indignity, and a soft little meow on
    /// top of it reads as two different cats. The tail is `shocked` and already
    /// has its own "喵……喵？！" to say; a second meow underneath it is one too
    /// many. That leaves being petted on the head, which is the only place he
    /// would let a sound slip out contentedly.
    private func meowIfBecoming(_ zone: PetTouchZone) {
        guard zone.strokeExpression == .smile, !isDialogueVisible else { return }
        meow()
    }

    private func startAfterglow() {
        afterglowSequence += 1
        let sequence = afterglowSequence
        afterglowImageName = PetExpression.kirakira.rawValue
        DispatchQueue.main.asyncAfter(deadline: .now() + PetTouchTuning.afterglow) {
            guard sequence == afterglowSequence else { return }
            afterglowImageName = nil
        }
    }

    private func interact() {
        let now = Date()
        lastInteraction = now
        lastTouchedAt = now

        // Wake on contact rather than on the next timer tick. Sleep is otherwise
        // re-evaluated once a second, which would leave the Zs drifting over the
        // top of him for up to a second after he has already reacted — and they
        // share a corner with the meow.
        wakeIfAsleep()

        let reaction = annoyance.registerPoke(at: now)
        startShake(reaction.shakeBeats)

        // Once he is working through the crescendo, prodding him only shakes
        // him. The lines advance from the dialogue box instead, so the burst of
        // clicks that set him off cannot also skip past what it provoked.
        if currentVoice == .pestered, isDialogueVisible {
            return
        }

        // Blowing up says nothing of its own — it is the same crescendo, just
        // shaken harder — so the build-up runs to its end uninterrupted.
        if reaction.isAgitated {
            present(PetPokeDialogue.pesteredPages, as: .pestered)
            return
        }

        // A poke is just a poke. Quota is a question, and it has its own menu
        // item — left-clicking used to open a usage report every time, which
        // drowned out everything else he might do.
        if isDialogueVisible {
            lastDialogueInteraction = now
            guard !isStageHeld(at: now) else { return }
            advanceDialogue()
            return
        }

        // An unhurried poke sometimes earns a remark. Only while he is still
        // tolerant: once he is irritated he is in no mood for small talk.
        // A poke that earns no remark is not nothing — a sound escapes him
        // instead. Reaching here already guarantees an empty dialogue box: the
        // visible-dialogue branch above returned, so the effect cannot land on
        // top of a line being read.
        guard reaction == .tolerated,
              Double.random(in: 0..<1) < PetAnnoyanceTuning.casualChance,
              let page = PetPokeDialogue.casualPage(avoiding: lastCasualLine)
        else {
            meow()
            return
        }

        if present([page], as: .casual) {
            lastCasualLine = page.message
        }
    }

    /// True while the current line is still owed its moment on screen. Further
    /// prodding shakes him, but cannot turn the page.
    private func isStageHeld(at time: Date) -> Bool {
        guard let stageHoldUntil else { return false }
        return time < stageHoldUntil
    }

    private func startShake(_ beats: [PetShakeBeat]) {
        shakeSequence += 1
        runShakeStep(sequence: shakeSequence, beats: beats, step: 0)
    }

    private func runShakeStep(sequence: Int, beats: [PetShakeBeat], step: Int) {
        guard sequence == shakeSequence else { return }
        guard step < beats.count else {
            shakeDegrees = 0
            return
        }

        shakeDegrees = beats[step].degrees
        DispatchQueue.main.asyncAfter(deadline: .now() + beats[step].duration) {
            runShakeStep(sequence: sequence, beats: beats, step: step + 1)
        }
    }

    private func startUsageDialogue() {
        present(CodexUsageReader.latestDialogue(), as: .quota)
    }

    /// Whether `voice` may take the dialogue box now.
    ///
    /// A free box is anyone's. A busy one only yields to a stronger voice, or —
    /// for an equal or lesser one — after the line has had its moment and there
    /// are no pages left to read.
    private func canTakeStage(_ voice: PetVoice, at time: Date) -> Bool {
        guard isDialogueVisible, let currentVoice else { return true }
        guard !voice.needsSilence else { return false }
        if voice > currentVoice { return true }

        let hadItsMoment = stageHoldUntil.map { time >= $0 } ?? true
        return hadItsMoment && dialoguePageIndex >= dialoguePages.count - 1
    }

    @discardableResult
    private func present(_ pages: [DialoguePage], as voice: PetVoice) -> Bool {
        let now = Date()
        guard !pages.isEmpty, canTakeStage(voice, at: now) else { return false }

        lastInteraction = now
        lastDialogueInteraction = now
        isDialogueAutoPlaying = false
        currentVoice = voice
        stageHoldUntil = now.addingTimeInterval(voice.hold)
        cancelBlink()
        dialoguePages = pages
        dialoguePageIndex = 0
        dialogueText = pages[0].message
        petExpression = pages[0].expression
        startDialogueMouthAnimation(for: pages[0])
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            isDialogueVisible = true
        }
        return true
    }

    private func interactWithDialogue() {
        let now = Date()
        lastInteraction = now
        lastTouchedAt = now
        lastDialogueInteraction = now
        guard !isStageHeld(at: now) else { return }

        let voice = currentVoice
        advanceDialogue()

        // Each page of a sequence is owed the same moment the first one got.
        if let voice, isDialogueVisible {
            stageHoldUntil = now.addingTimeInterval(voice.hold)
        }
    }

    private func advanceDialogue() {
        let nextPageIndex = dialoguePageIndex + 1
        guard nextPageIndex < dialoguePages.count else {
            hideDialogue()
            return
        }

        dialoguePageIndex = nextPageIndex
        dialogueText = dialoguePages[nextPageIndex].message
        petExpression = dialoguePages[nextPageIndex].expression
        startDialogueMouthAnimation(for: dialoguePages[nextPageIndex])
    }

    private func hideDialogue() {
        // Hearing the crescendo out is what settles him, so reaching its end
        // drops him back to calm rather than leaving the decay to finish the job.
        if currentVoice == .pestered {
            annoyance.reset()
        }
        currentVoice = nil

        cancelDialogueMouthAnimation()
        withAnimation(.easeOut(duration: 0.16)) {
            isDialogueVisible = false
        }
        dialoguePages = []
        dialoguePageIndex = 0
        lastDialogueInteraction = nil
        isDialogueAutoPlaying = false
        stageHoldUntil = nil
        petExpression = .regular
    }

    private func hideDialogueIfTimedOut(at now: Date) {
        guard isDialogueVisible,
              !isDialogueAutoPlaying,
              let lastDialogueInteraction,
              let currentVoice,
              now.timeIntervalSince(lastDialogueInteraction) >= currentVoice.clearsAfter
        else {
            return
        }

        hideDialogue()
    }

    /// Drops the sleeping state immediately, for the moments that should not
    /// wait on the next tick to look awake.
    private func wakeIfAsleep() {
        guard isAsleep else { return }
        isAsleep = false
        dozeSequence += 1
        dozeImageName = nil
        isShowingSleepZs = false
    }

    private func updateSleep(at now: Date) {
        let asleep = PetSleep.isAsleep(
            at: now,
            sinceTouched: now.timeIntervalSince(lastTouchedAt)
        )
        guard asleep != isAsleep else { return }
        isAsleep = asleep
        if asleep {
            cancelBlink()
            startDozing()
        } else {
            // Waking is a start, not a fade: whatever roused him gets the frame
            // immediately.
            dozeSequence += 1
            dozeImageName = nil
            isShowingSleepZs = false
        }
    }

    private func startDozing() {
        dozeSequence += 1
        runDozeStep(sequence: dozeSequence, step: 0)
    }

    private func runDozeStep(sequence: Int, step: Int) {
        guard sequence == dozeSequence else { return }
        guard step < PetSleep.dozeOff.count else {
            // Handing over to the steady sleeping face has to be a plain swap.
            // Fading the Zs in from inside the same transaction cross-faded the
            // sprite along with them, which left the last half-closed frame
            // hanging around for the length of the fade rather than the length
            // of the beat.
            dozeImageName = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard sequence == dozeSequence else { return }
                withAnimation(.easeIn(duration: 0.35)) {
                    isShowingSleepZs = true
                }
            }
            return
        }

        let beat = PetSleep.dozeOff[step]
        dozeImageName = beat.imageName
        DispatchQueue.main.asyncAfter(deadline: .now() + beat.duration) {
            runDozeStep(sequence: sequence, step: step + 1)
        }
    }

    /// The one thing he says without being asked. Every guard lives in
    /// `PetNightWatch`; this only supplies the readings and speaks the result.
    private func considerSpeakingUp(at now: Date) {
        guard touch.isPetVisible, !PetQuietHours.isQuiet(at: now) else { return }

        let sinceSpontaneous = lastSpontaneousAt.map { now.timeIntervalSince($0) } ?? .infinity
        let sinceInteraction = now.timeIntervalSince(lastInteraction)
        let idle = PetSystemIdle.seconds()

        // The chime goes first: it is the one tied to a particular minute, while
        // the nagging can just as well come later.
        if let struck = hourChime.consider(
            now: now,
            userIdle: idle,
            sinceInteraction: sinceInteraction
        ) {
            let pages = PetDialogueBook.shared
                .pages(for: struck.scenario)
                .filling(["hour": PetHourChime.spoken(hour: struck.hour)])
            if let page = pages.randomPage(avoiding: nil), present([page], as: .spontaneous) {
                hourChime.confirm()
                PetQuietHours.lastChimedHour = hourChime.chimedHour
                noteSpontaneous(at: now)
            }
            return
        }

        guard let scenario = nightWatch.consider(
            now: now,
            userIdle: idle,
            sinceInteraction: sinceInteraction,
            sinceSpontaneous: sinceSpontaneous
        ),
        let page = PetDialogueBook.shared
            .pages(for: scenario)
            .randomPage(avoiding: lastSpontaneousLine)
        else {
            return
        }

        if present([page], as: .spontaneous) {
            nightWatch.confirm()
            PetQuietHours.nightSpokenSlot = nightWatch.spokenSlot
            lastSpontaneousLine = page.message
            noteSpontaneous(at: now)
        }
    }

    private func noteSpontaneous(at time: Date) {
        lastSpontaneousAt = time
        PetQuietHours.lastSpontaneousAt = time
    }

    private func triggerBlinkIfNeeded(at now: Date) {
        guard now >= nextBlinkAt else { return }
        nextBlinkAt = now.addingTimeInterval(Double.random(in: 3...6))
        // A blink on top of the stroking squint would just look like a twitch,
        // and his eyes are already shut when he is asleep.
        guard !isDialogueVisible, !isAsleep, touch.strokedZone == nil else { return }

        blinkSequence += 1
        let sequence = blinkSequence
        let lid = PetBlinkTiming.lid
        let shut = PetBlinkTiming.shut
        blinkImageName = "blink-half"

        DispatchQueue.main.asyncAfter(deadline: .now() + lid) {
            guard sequence == blinkSequence else { return }
            blinkImageName = "blink"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + lid + shut) {
            guard sequence == blinkSequence else { return }
            blinkImageName = "blink-half"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + lid + shut + lid) {
            guard sequence == blinkSequence else { return }
            blinkImageName = nil
        }
    }

    private func cancelBlink() {
        blinkSequence += 1
        blinkImageName = nil
    }

    private func startDialogueMouthAnimation(for page: DialoguePage) {
        startMouthAnimation(for: page.expression)
    }

    private func startMouthAnimation(
        for expression: PetExpression,
        completion: (() -> Void)? = nil
    ) {
        dialogueMouthSequence += 1
        let sequence = dialogueMouthSequence
        let frames = expression.mouthFrames
        let rhythm = mouthRhythm(for: expression, frames: frames)
        runDialogueMouthStep(
            sequence: sequence,
            frames: frames,
            rhythm: rhythm,
            step: 0,
            completion: completion
        )
    }

    private func mouthRhythm(
        for expression: PetExpression,
        frames: DialogueMouthFrames
    ) -> [DialogueMouthBeat] {
        if expression == .kirakira {
            return [
                DialogueMouthBeat(imageName: frames.halfOpen, duration: 0.20),
                DialogueMouthBeat(imageName: frames.open, duration: 0.26),
                DialogueMouthBeat(imageName: frames.halfOpen, duration: 0.20),
                DialogueMouthBeat(imageName: frames.closed, duration: 0.24),
                DialogueMouthBeat(imageName: frames.halfOpen, duration: 0.18),
                DialogueMouthBeat(imageName: frames.open, duration: 0.24),
                DialogueMouthBeat(imageName: frames.halfOpen, duration: 0.13),
                DialogueMouthBeat(imageName: frames.open, duration: 0.24),
                DialogueMouthBeat(imageName: frames.halfOpen, duration: 0.22)
            ]
        }

        return [
            DialogueMouthBeat(imageName: frames.open, duration: 0.28),
            DialogueMouthBeat(imageName: frames.closed, duration: 0.22),
            DialogueMouthBeat(imageName: frames.open, duration: 0.30),
            DialogueMouthBeat(imageName: frames.closed, duration: 0.32),
            DialogueMouthBeat(imageName: frames.open, duration: 0.20),
            DialogueMouthBeat(imageName: frames.halfOpen, duration: 0.09),
            DialogueMouthBeat(imageName: frames.open, duration: 0.20),
            DialogueMouthBeat(imageName: frames.closed, duration: 0.24)
        ]
    }

    private func runDialogueMouthStep(
        sequence: Int,
        frames: DialogueMouthFrames,
        rhythm: [DialogueMouthBeat],
        step: Int,
        completion: (() -> Void)? = nil
    ) {
        guard sequence == dialogueMouthSequence else { return }
        guard step < rhythm.count else {
            dialogueMouthImageName = frames.closed
            completion?()
            return
        }

        let beat = rhythm[step]
        dialogueMouthImageName = beat.imageName
        DispatchQueue.main.asyncAfter(deadline: .now() + beat.duration) {
            runDialogueMouthStep(
                sequence: sequence,
                frames: frames,
                rhythm: rhythm,
                step: step + 1,
                completion: completion
            )
        }
    }

    private func cancelDialogueMouthAnimation() {
        dialogueMouthSequence += 1
        dialogueMouthImageName = nil
    }
}

private struct DialogueMouthBeat {
    let imageName: String
    let duration: TimeInterval
}

private struct PersonaDialogueBox: View {
    let message: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            PersonaDialogueShape()
                .fill(Color.black.opacity(0.96))
                .overlay {
                    PersonaDialogueShape()
                        .stroke(.black, lineWidth: 11)
                }
                .overlay {
                    PersonaDialogueShape()
                        .stroke(.white, lineWidth: 4)
                }

            Text(message)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineSpacing(4)
                .padding(.leading, 96)
                .padding(.trailing, 34)
                .padding(.top, 57)

            ZStack {
                PersonaNamePlateShape()
                    .fill(.white)
                    .overlay {
                        PersonaNamePlateShape()
                            .stroke(.black, lineWidth: 8)
                    }

                HStack(spacing: 0) {
                    Text("摩")
                    Text("尔")
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 23)
                        .background(.black)
                    Text("加纳")
                }
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(.black)
                    .padding(.leading, 12)
            }
            .frame(
                width: PetLayout.namePlateSize.width,
                height: PetLayout.namePlateSize.height
            )
            .rotationEffect(PetLayout.namePlateRotation)
            .offset(
                x: PetLayout.namePlateOffset.width,
                y: PetLayout.namePlateOffset.height
            )
        }
    }
}

private struct PersonaDialogueShape: Shape {
    func path(in rect: CGRect) -> Path {
        DialogueBalloonGeometry.path(
            through: DialogueBalloonGeometry.balloonPoints(in: rect)
        )
    }
}

private struct PersonaNamePlateShape: Shape {
    func path(in rect: CGRect) -> Path {
        DialogueBalloonGeometry.path(
            through: DialogueBalloonGeometry.namePlatePoints(in: rect)
        )
    }
}

private struct PetSprite: View {
    var imageName: String
    var isBreathing: Bool
    var shakeDegrees: Double
    var leanDegrees: Double

    var body: some View {
        ZStack {
            if let image = NSImage(named: imageName) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 4)
            } else {
                PersonaInspiredCat()
                    .shadow(color: .black.opacity(0.26), radius: 5, x: 0, y: 4)
            }

        }
        .scaleEffect(isBreathing ? 1.03 : 0.97)
        .rotationEffect(.degrees(shakeDegrees))
        .rotationEffect(.degrees(leanDegrees))
        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: isBreathing)
        // Snappy enough to land each beat of a shake inside its own ~0.11s slot,
        // while still leaving a single poke a little bounce.
        .animation(.spring(response: 0.15, dampingFraction: 0.55), value: shakeDegrees)
        // Slower and better damped: he follows the hand rather than snapping to
        // it, which is what makes the lean read as leaning in.
        .animation(.spring(response: 0.30, dampingFraction: 0.75), value: leanDegrees)
    }
}

/// Sleep Zs drifting off to his side: three of them on one loop, each starting a
/// beat after the last so there is always one on its way up.
private struct SleepingZs: View {
    @State private var isDrifting = false

    private static let count = 3
    private static let cycle: Double = 3.6

    var body: some View {
        ZStack {
            ForEach(0..<Self.count, id: \.self) { index in
                Text("Z")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .scaleEffect(isDrifting ? 1.3 : 0.6)
                    .offset(x: isDrifting ? 20 : 0, y: isDrifting ? -42 : 0)
                    .opacity(isDrifting ? 0 : 0.95)
                    .animation(
                        .easeOut(duration: Self.cycle)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * Self.cycle / Double(Self.count)),
                        value: isDrifting
                    )
            }
        }
        .onAppear { isDrifting = true }
    }
}

private struct PersonaInspiredCat: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(.black)
                .frame(width: 150, height: 132)
                .offset(y: 12)

            ear(x: -52, rotation: -18)
            ear(x: 52, rotation: 18)

            Ellipse()
                .fill(Color(red: 0.78, green: 0.78, blue: 0.72))
                .frame(width: 88, height: 92)
                .offset(y: 21)

            scarf
                .offset(x: -5, y: 75)

            eye(x: -34)
            eye(x: 34)

            Capsule()
                .fill(.black)
                .frame(width: 18, height: 7)
                .offset(y: 19)

            RoundedRectangle(cornerRadius: 9)
                .stroke(.black, lineWidth: 4)
                .frame(width: 42, height: 20)
                .offset(y: 43)
        }
    }

    private func ear(x: CGFloat, rotation: Double) -> some View {
        Triangle()
            .fill(.black)
            .frame(width: 56, height: 68)
            .overlay(
                Triangle()
                    .fill(Color(red: 0.06, green: 0.2, blue: 0.35))
                    .padding(14)
            )
            .rotationEffect(.degrees(rotation))
            .offset(x: x, y: -52)
    }

    private func eye(x: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 42, height: 56)

            Capsule()
                .fill(Color(red: 0.0, green: 0.42, blue: 0.9))
                .frame(width: 16, height: 36)
        }
        .offset(x: x, y: -9)
    }

    private var scarf: some View {
        ZStack {
            Polygon(points: [
                CGPoint(x: 0.0, y: 0.1),
                CGPoint(x: 1.0, y: 0.0),
                CGPoint(x: 0.7, y: 1.0)
            ])
            .fill(Color(red: 0.98, green: 0.82, blue: 0.06))
            .frame(width: 80, height: 46)
            .rotationEffect(.degrees(-8))

            Polygon(points: [
                CGPoint(x: 0.0, y: 0.0),
                CGPoint(x: 1.0, y: 0.16),
                CGPoint(x: 0.35, y: 1.0)
            ])
            .fill(Color(red: 0.98, green: 0.82, blue: 0.06))
            .frame(width: 58, height: 52)
            .offset(x: 46, y: 8)
            .rotationEffect(.degrees(11))
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct Polygon: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height))
        }
        path.closeSubpath()
        return path
    }
}
