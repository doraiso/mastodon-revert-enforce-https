# $B%G%#%9%H%j%S%e!<%7%g%sJL<B9T%,%$%I(B

$B%G%#%9%H%j%S%e!<%7%g%sJL$N5/F0Nc0lMw$G$9(B

# Container-Optimized OS 68-10718.86.0 stable

* mastodon.sh $B$O(B ./mastodon.sh $B$G$O<B9T$G$-$^$;$s!#(Bbash mastodon.sh $B$G<B9T$7$F$/$@$5$$!#(B
* $B8x3+80$rEPO?$7!"$=$N%-!<$G%$%s%9%?%s%9$K%m%0%$%s$7$F$/$@$5$$!#(B

	$ ssh [$B%f!<%6L>(B]@[$B%Q%9%o!<%I(B]
	$ git clone https://github.com/mamemomonga/mstdn-revert-enforce-https.git
	$ cd mstdn-revert-enforce-https
	$ cp docker-compose/mstdn-revert-enforce-https.yml docker-compose.yml
	$ bash mastodon.sh create

$BJL%?!<%_%J%k$+$i<B9T(B

	$ ssh -L 3000:localhost:3000 -L 1080:localhost:1080 [$B%f!<%6L>(B]@[$B%Q%9%o!<%I(B]

http://localhost:3000/ $B$G%^%9%H%I%s!"(Bhttp://localhost:1080/ $B$G%a!<%k(B $B$,8+$($l$P@.8y$G$9!#(B

