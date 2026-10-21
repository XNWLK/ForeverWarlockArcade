// Runs every check in turn and stops at the first that fails.
//   node tools/check-all.js
const { execFileSync } = require('child_process'), path = require('path');
const checks = [['stamp.js', '--check'], ['check-api.js'], ['check-layout.js'], ['check-shard.js', '20'], ['check-juggler.js', '4'], ['check-higher.js', '20'], ['check-warlockle.js', '200'], ['check-ware.js', '6'], ['check-pegs.js', '4'], ['check-taptap.js'], ['check-merge.js', '10'], ['check-circles.js'], ['check-connections.js'], ['check-iconle.js'], ['check-typing.js'], ['check-gems.js', '3'], ['check-sweeper.js', '6'], ['check-flappy.js'], ['check-rotation.js', '600'], ['check-monkey.js', '400'], ['check-monkey.js', '200', '7', 'game'], ['check-lua51.js']];
for (const [file, ...args] of checks) {
  process.stdout.write(file + ': ');
  try { process.stdout.write(execFileSync('node', [path.join(__dirname, file), ...args], { encoding: 'utf8' }).trim().split('\n').slice(-2).join(' | ') + '\n'); }
  catch (e) { console.log('FAILED\n' + (e.stdout || '') + (e.stderr || '')); process.exit(1); }
}
console.log('ALL OK');
