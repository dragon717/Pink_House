package com.pinkhouse.android.feature.pet

import androidx.lifecycle.ViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

enum class PetCharacter(
    val id: String,
    val displayName: String,
    val catchphrase: String,
) {
    Naicha("naicha", "奶茶", "喵~"),
    Maomao("maomao", "毛毛", "汪~"),
}

enum class PetPanelState {
    Hidden,
    Collapsed,
    Expanded,
}

enum class PetShopTab {
    Inventory,
    Shop,
}

data class PetHomeMessage(
    val id: Long,
    val text: String,
)

data class PetUiState(
    val selectedPet: PetCharacter = PetCharacter.Naicha,
    val hunger: Int = 68,
    val hygiene: Int = 76,
    val energy: Int = 72,
    val mood: Int = 82,
    val meowCoin: Int = 120,
    val fishCoin: Int = 36,
    val boneCoin: Int = 28,
    val isWorking: Boolean = false,
    val showStatusBars: Boolean = true,
    val panelState: PetPanelState = PetPanelState.Hidden,
    val selectedShopTab: PetShopTab = PetShopTab.Inventory,
    val messages: List<PetHomeMessage> = listOf(
        PetHomeMessage(0, "欢迎回来呀，我会用本地规则陪你玩，不偷跑 AI。"),
    ),
)

class PetViewModel : ViewModel() {
    private var nextMessageId = 1L
    private val _uiState = MutableStateFlow(PetUiState())
    val uiState: StateFlow<PetUiState> = _uiState.asStateFlow()

    fun switchPet(pet: PetCharacter) {
        _uiState.update { state ->
            state.copy(selectedPet = pet)
                .withMessage("${pet.displayName}已经跑到你面前啦，${pet.catchphrase}")
        }
    }

    fun toggleStatusBars() {
        _uiState.update { state ->
            state.copy(showStatusBars = !state.showStatusBars)
        }
    }

    fun setPanelState(panelState: PetPanelState) {
        _uiState.update { state -> state.copy(panelState = panelState) }
    }

    fun setShopTab(tab: PetShopTab) {
        _uiState.update { state ->
            state.copy(selectedShopTab = tab, panelState = PetPanelState.Collapsed)
        }
    }

    fun feed() {
        _uiState.update { state ->
            val current = state.selectedPet
            val updated = when (current) {
                PetCharacter.Naicha -> state.copy(
                    hunger = (state.hunger + 14).coerceAtMost(100),
                    mood = (state.mood + 4).coerceAtMost(100),
                    fishCoin = (state.fishCoin - 1).coerceAtLeast(0),
                )
                PetCharacter.Maomao -> state.copy(
                    hunger = (state.hunger + 14).coerceAtMost(100),
                    mood = (state.mood + 4).coerceAtMost(100),
                    boneCoin = (state.boneCoin - 1).coerceAtLeast(0),
                )
            }
            updated.withMessage("${current.displayName}吃饱了一点，开心地蹭了蹭你。")
        }
    }

    fun drink() {
        _uiState.update { state ->
            state.copy(
                hunger = (state.hunger + 4).coerceAtMost(100),
                energy = (state.energy + 8).coerceAtMost(100),
            ).withMessage("${state.selectedPet.displayName}喝完水，精神恢复了一些。")
        }
    }

    fun clean() {
        _uiState.update { state ->
            state.copy(
                hygiene = 100,
                mood = (state.mood + 6).coerceAtMost(100),
            ).withMessage("${state.selectedPet.displayName}现在香香软软，适合继续陪你整理衣橱。")
        }
    }

    fun pet() {
        _uiState.update { state ->
            state.copy(
                mood = (state.mood + 8).coerceAtMost(100),
                energy = (state.energy - 2).coerceAtLeast(0),
            ).withMessage("${state.selectedPet.displayName}眯起眼睛享受摸摸，${state.selectedPet.catchphrase}")
        }
    }

    fun toggleWork() {
        _uiState.update { state ->
            if (state.isWorking) {
                state.copy(
                    isWorking = false,
                    meowCoin = state.meowCoin + 20,
                    energy = (state.energy - 8).coerceAtLeast(0),
                    mood = (state.mood + 3).coerceAtMost(100),
                ).withMessage("${state.selectedPet.displayName}打工回来，带回 20 个喵币。")
            } else {
                state.copy(
                    isWorking = true,
                    energy = (state.energy - 10).coerceAtLeast(0),
                    mood = (state.mood - 3).coerceAtLeast(0),
                ).withMessage("${state.selectedPet.displayName}出门打工啦，稍后记得接它回家。")
            }
        }
    }

    private fun PetUiState.withMessage(text: String): PetUiState =
        copy(messages = (messages + PetHomeMessage(nextMessageId++, text)).takeLast(4))
}
