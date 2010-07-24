#!/usr/bin/ruby

# params:
# -R	randomize files		(keeps subsequent files with increasing _\d+ suffix together) (1x02-Ep_1.avi and 1x03-Ep_2.avi will be kept together but 1x02-Ep1.avi and 1x03-Ep2.avi won't)
# -R/	randomize dirs		(randomizes order of directories but not the files within)
# -R1	randomize files | head -n1		(same as -R but play only the first file)
# 	(works for any number)
# -DF		-framedrop -fs
# -X	exclude extension	(-X jpeg will ignore all .jpeg files) (note that mpl excludes some extensions by default, grep rejary)
# any other args are passed to mplayer, but note you have to use -ao=null instead of -ao null (for all options with params)


# compatibility with older ruby versions
unless String.new.respond_to? "start_with?"
	class String
		def start_with?(s)
			self.match /^#{s}/
		end
	end
end

# split args into files and options
def split_ary(ary)
	a = []
	b = []
	c = false
	ary.each do |i|
		next if i == '-'
		if i == '--' then
			c = true
			next
		end
		a << i if c or not (i =~ /^-/)
		b << i if (not c) and (i =~ /^-/)
	end
	[a, b]
end
(files, opts) = split_ary(ARGV)

# parse opts
randomize = ! opts.select { |s| s.start_with? "-R" }.empty?
justone = opts.select { |s| s =~ /^-R\d+$/ }.first.sub(/^-R/, '').to_i rescue 0
sortdir = opts.include? "-R/"
exclude = opts.select { |s| s.start_with? "-X=" }.map { |s| s.sub(/^-X=/, '') }
opts = [opts, "-framedrop", "-fs"].flatten if opts.include? '-DF'
opts.reject! { |s| s.start_with?("-R") or (s == '-DF') or s.start_with?("-X=") }

rejary = ['sub', 'srt', 'txt', 'pdf', 'tgz', 'rb', 'pdf', 'jpg', 'idx', 'zip', 'png', 'gif', 'JPG', 'jpeg', 'ps', 'py', 'gz', 'bz2', 'h', 'o', 'c', exclude].flatten.map { |x| "." + x.downcase }



# volume controls: mpc version, obsolete, used if amixer version fails

# save volume and play/paused state, pause if playing
def snd_save_mpc
	@play_state = `mpc | sed -n 2p`.chomp.sub(/^\s*\[(.*)\].*$/, '\1')
	`mpc toggle` if @play_state == "playing"

	volume = `mpc | sed -n 3p`.chomp.sub(/^.*volume:\s*([0-9]*).*$/, '\1')
	if volume.to_i == volume
		@volume = volume
		return
	end
	raise volume
end

# restore volume and play/paused state
def snd_restore_mpc
	`mpc volume #{@volume}`
	p [:snd_restore_mpc, @volume]
	`mpc toggle` if @play_state == "playing"
end

# alsa version

def snd_save_amixer
	@play_state = 'unknown'

	volume = []
	['Master', 'PCM'].each do |d|
		vals = `amixer sget #{d}`.map(&:chomp).select do |l|
			l.sub!(/^.*?\s(\d+)\s+\[\d+%\].*$/, '\1')
		end
		val = vals.first.to_i
		volume << val
	end
	if volume[0].to_i == volume[0] and volume[1] == volume[1].to_i
		@volume = volume
		return
	end
	raise volume
end

def snd_restore_amixer
	p [:snd_restore_amixer, @volume]
	`amixer sset Master #{@volume[0]}`
	`amixer sset PCM #{@volume[1]}`
end

# dispatchers

def snd_save
	snd_save_amixer rescue $stderr.puts "snd_save_amixer failed"
	snd_save_mpc rescue $stderr.puts "snd_save_mpc failed"

	p @volume
end

def snd_restore
	if Array === @volume
		snd_restore_amixer
	else
		snd_restore_mpc
	end
end


def mplayer( a, b )
	system("mplayer", *(a + b))
end

# play current dir if no files
if files.empty? then
	files = Dir["*"].sort
end

files.map! do |fn|
	if File.exists? fn then		# existing files
		# "recurse" one dir
		if File.directory? fn then
			Dir[fn + "/*"].sort
		else
			fn
		end
	elsif fn.match(/^[a-z]+:\/+[a-zA-Z]+/)		# remote adresses
		fn
	else		# not found, find in given or current dir or locate if not found
		dn = File.dirname fn
		bn = File.basename fn
		pt = "#{dn}/*#{bn}*"
		if Dir[pt].empty? then
			`locate "#{bn}"`.split(/\n/).sort
		else
			Dir[pt].sort
		end
	end
end
files.flatten!

files.reject! do |fn|
	# remove subdirs
	if File.directory? fn
		true
	else	# and files with rejary extensions
		ext = (fn.sub(/^.*(\.[^.]*)$/, '\1') rescue "x")
		if ext[0..0] != "." then
			false
		else
			rejary.include? ext.downcase
		end
	end
end

# remove duplicates
files.uniq!
srand

# randomize array
class Array
	def shuffle!
		each_index do |i|
			j = rand(length - i) + i
			self[j], self[i] = self[i], self[j]
		end
	end
	
	def shuffle
		dup.shuffle!
	end
end

# if all files are in 1 dir, add options from $dir/.mpl
newopts = []
dircount = 0
files.map { |f| File.dirname(f) }.uniq.each do |i|	# sort not necessary
	x = `cat "#{i}/.mpl"`.chomp.split /\s+/
	newopts << x unless x.empty?
	dircount += 1
end
opts << newopts unless dircount > 1

# convert -ao=null to -ao null
opts = opts.flatten.map do |o|
	if (o =~ /^(-.+?)=([^\s].*)$/)
		o = [$1, $2]
	end
	o
end

# -R or -R\d+
if randomize and !sortdir
	# merge 1x02-Ep_1.avi and 1x03-Ep_2.avi together
	q = 0
	a = []
	f = []
	0.upto(files.size - 1) do |i|
		if q == 0
			if files[i].match /_(0|0*1)+\.\w{2,5}$/
				q = 1
				a << files[i]
				next
			end
		elsif q == 1
			if files[i].match /_\d+\.\w{2,5}$/
				a << files[i]
				next
			else
				f << a
				a = []
				q = 0
				next
			end
		else
			raise q
		end
		f << files[i]
	end
	f << a unless a.empty?

	# and shuffle
	files = f.shuffle.flatten
end

# -R\d+
files = files[0..justone - 1] if justone != 0

# -R/
if sortdir
	dirhash = {}
	files.map do |f|
		d = File.dirname f
		dirhash[d] = [] if dirhash[d].nil?
		dirhash[d] << f
	end
	files = []
	dirhash.keys.shuffle.each do |d|
		files += dirhash[d]
	end
end
p files

# switch on screen, switch off screensaver
snd_save unless opts.include? ["-ao", "null"]
`xset dpms force on`
`xscreensaver-command -deactivate`
`killall -STOP xscreensaver`

# run mplayer
mplayer(opts.flatten, files.flatten)

# clean up, deactivate xscreensaver
`killall -CONT xscreensaver`
snd_restore unless opts.include? ["-ao", "null"]
`xscreensaver-command -deactivate`

__END__
