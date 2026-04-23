package com.pinkhouse.android.core.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

@Composable
fun PinkFullHeightSheet(
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    heightFraction: Float = 0.95f,
    content: @Composable ColumnScope.() -> Unit,
) {
    val scrimInteraction = remember { MutableInteractionSource() }
    Dialog(
        onDismissRequest = onDismissRequest,
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false,
            dismissOnBackPress = true,
            dismissOnClickOutside = true,
        ),
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.28f))
                .clickable(
                    interactionSource = scrimInteraction,
                    indication = null,
                    onClick = onDismissRequest,
                ),
        ) {
            Surface(
                modifier = modifier
                    .align(Alignment.BottomCenter)
                    .statusBarsPadding()
                    .navigationBarsPadding()
                    .fillMaxWidth()
                    .fillMaxHeight(heightFraction),
                shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
                color = Color.White,
                tonalElevation = 12.dp,
                shadowElevation = 18.dp,
            ) {
                Column(modifier = Modifier.fillMaxSize()) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 10.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Spacer(
                            modifier = Modifier
                                .height(5.dp)
                                .fillMaxWidth(0.14f)
                                .background(Color(0xFFD8CCD2), CircleShape),
                        )
                    }
                    content()
                }
            }
        }
    }
}

@Composable
fun PinkSheetHeader(
    title: String,
    modifier: Modifier = Modifier,
    leading: @Composable RowScope.() -> Unit,
    trailing: @Composable RowScope.() -> Unit = {},
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 18.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            modifier = Modifier.weight(1f),
            verticalAlignment = Alignment.CenterVertically,
            content = leading,
        )
        Text(
            text = title,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
        )
        Row(
            modifier = Modifier.weight(1f),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = androidx.compose.foundation.layout.Arrangement.End,
            content = trailing,
        )
    }
}
