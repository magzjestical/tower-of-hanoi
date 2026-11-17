// Shared controller: talks to the Prolog API; each design supplies its own UI.
const Hanoi = (() => {
  const S = {pegs: [[], [], []], n: 4, moves: 0, sel: null, hint: null, busy: false, optimal: 0, left: 0, log: []};
  let tok = 0, ui = {render() {}, say() {}, busy() {}};
  const N = 'ABC';

  async function api(p, b) {
    try {
      const r = await fetch('/api/' + p, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(b)});
      return await r.json();
    } catch (e) {
      ui.say('Can’t reach the Prolog server. Start it with: swipl server.pl', 'err');
      return {ok: false, offline: true};
    }
  }
  const take = d => { S.pegs = d.pegs; S.optimal = d.optimal; S.left = d.remaining; };

  async function newGame(n) {
    tok++; S.busy = false; ui.busy(false); S.sel = null; S.hint = null; S.moves = 0; S.log = []; S.n = n;
    const d = await api('new', {n});
    if (!d.ok) return;
    take(d); ui.render(S);
    ui.say('Pick a peg to lift its top disk, then choose where to drop it.');
  }

  async function move(f, t) {
    const top = S.pegs[f][0];
    const d = await api('move', {pegs: S.pegs, from: f, to: t});
    if (!d.ok) { if (!d.offline) ui.say(d.error, 'err', t); return false; }
    S.moves++; S.hint = null; S.log.push(`${S.moves}. Disk ${top}: ${N[f]} → ${N[t]}`);
    take(d); ui.render(S);
    if (d.won) ui.say(S.moves === d.optimal ? `Perfect! Solved in the minimum ${S.moves} moves.`
                                            : `Solved in ${S.moves} moves (minimum is ${d.optimal}).`, 'win');
    else ui.say(`Moved ${N[f]} → ${N[t]}.`);
    return true;
  }

  async function click(i) {
    if (S.busy) return;
    if (S.sel === null) {
      if (!S.pegs[i].length) { ui.say('That peg is empty. Pick one that has a disk.', 'err', i); return; }
      S.sel = i; ui.render(S); ui.say(`Lifted disk ${S.pegs[i][0]} from ${N[i]}. Where to?`);
    } else {
      const f = S.sel; S.sel = null; ui.render(S);
      if (f === i) { ui.say('Disk put back.'); return; }
      await move(f, i);
    }
  }

  async function hint() {
    if (S.busy) return;
    const d = await api('solve', {pegs: S.pegs});
    if (!d.ok) return;
    if (!d.moves.length) { ui.say('Nothing left to do. It’s solved!', 'win'); return; }
    S.hint = d.moves[0]; S.sel = null; ui.render(S);
    ui.say(`Hint: move the top disk from ${N[S.hint.from]} to ${N[S.hint.to]}.`);
  }

  async function auto() {
    if (S.busy) return;
    const my = ++tok;
    const d = await api('solve', {pegs: S.pegs});
    if (!d.ok || !d.moves.length) return;
    S.busy = true; S.sel = null; S.hint = null; ui.busy(true); ui.render(S);
    for (const m of d.moves) {
      if (my !== tok) return;
      if (!(await move(m.from, m.to))) break;
      await new Promise(r => setTimeout(r, Math.max(150, 650 - S.n * 55)));
    }
    if (my === tok) { S.busy = false; ui.busy(false); }
  }

  return {S, bind: u => { ui = u; }, newGame, click, hint, auto};
})();
