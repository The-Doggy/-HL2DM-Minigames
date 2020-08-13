//double-include prevention
#if defined _cold_minigames_
#endinput
#endif
#define _cold_minigames_

public SharedPlugin __pl_cold_minigames =
{
	name = "cold_minigames",
	file = "cold_minigames.smx",
//	#if defined REQUIRE_PLUGIN
//		required = 1,
//	#else
		required = 0,
//	#endif
};

native bool IsClientInMinigame(int Client);

public void __pl_cold_minigames_SetNTVOptional()
{
	MarkNativeAsOptional("IsClientInMinigame");
}