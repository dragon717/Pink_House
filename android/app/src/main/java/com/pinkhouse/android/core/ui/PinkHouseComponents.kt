package com.pinkhouse.android.core.ui

import androidx.annotation.DrawableRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage

@Composable
fun PinkSurfaceScaffold(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(PinkHouseDesignTokens.Background, PinkHouseDesignTokens.BackgroundDeep),
                ),
            ),
    ) {
        content()
    }
}

@Composable
fun PinkSegmentedTabs(
    tabs: List<String>,
    selectedIndex: Int,
    onSelected: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(PinkHouseDesignTokens.PlatterRadius),
        color = Color.White.copy(alpha = 0.74f),
    ) {
        Row(
            modifier = Modifier.padding(4.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            tabs.forEachIndexed { index, label ->
                Surface(
                    modifier = Modifier.clickable { onSelected(index) },
                    shape = RoundedCornerShape(22.dp),
                    color = if (index == selectedIndex) Color.White else Color.Transparent,
                ) {
                    Text(
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                        text = label,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = if (index == selectedIndex) FontWeight.Bold else FontWeight.Medium,
                        color = if (index == selectedIndex) PinkHouseDesignTokens.Primary else PinkHouseDesignTokens.TextMuted,
                    )
                }
            }
        }
    }
}

@Composable
fun PinkToolbarCluster(
    modifier: Modifier = Modifier,
    content: @Composable RowScope.() -> Unit,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(PinkHouseDesignTokens.PlatterRadius),
        color = Color.White.copy(alpha = 0.78f),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
            content = content,
        )
    }
}

@Composable
fun PinkIconButton(
    imageVector: ImageVector,
    contentDescription: String,
    modifier: Modifier = Modifier,
    badge: String? = null,
    onClick: () -> Unit,
) {
    Box(contentAlignment = Alignment.TopEnd) {
        IconButton(
            modifier = modifier.size(38.dp),
            onClick = onClick,
        ) {
            Icon(
                imageVector = imageVector,
                contentDescription = contentDescription,
                tint = PinkHouseDesignTokens.TextPrimary,
            )
        }
        if (badge != null) {
            Surface(
                shape = CircleShape,
                color = PinkHouseDesignTokens.Accent,
                modifier = Modifier.size(16.dp),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        text = badge,
                        color = Color.White,
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
            }
        }
    }
}

@Composable
fun PinkBottomNavBar(
    modifier: Modifier = Modifier,
    content: @Composable RowScope.() -> Unit,
) {
    Surface(
        modifier = modifier
            .padding(horizontal = 18.dp)
            .padding(bottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() + 8.dp)
            .height(PinkHouseDesignTokens.BottomNavHeight),
        shape = RoundedCornerShape(36.dp),
        color = Color.White.copy(alpha = 0.86f),
        tonalElevation = 8.dp,
        shadowElevation = 4.dp,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
            content = content,
        )
    }
}

@Composable
fun RowScope.PinkBottomNavItem(
    selected: Boolean,
    label: String,
    icon: ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    NavigationBarItem(
        modifier = modifier,
        selected = selected,
        onClick = onClick,
        icon = { Icon(icon, contentDescription = label) },
        label = { Text(label, maxLines = 1) },
    )
}

@Composable
fun PetChatFloatingButton(
    @DrawableRes petImageRes: Int,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.size(PinkHouseDesignTokens.PetFloatingSize),
        shape = CircleShape,
        color = Color.White.copy(alpha = 0.9f),
        tonalElevation = 8.dp,
        shadowElevation = 6.dp,
        onClick = onClick,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Image(
                painter = painterResource(petImageRes),
                contentDescription = "萌宠对话",
                modifier = Modifier
                    .size(width = 64.dp, height = 50.dp)
                    .clip(CircleShape),
                contentScale = ContentScale.Fit,
            )
        }
    }
}

@Composable
fun AssetImage(
    model: Any?,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Crop,
    placeholderIcon: ImageVector? = null,
    cornerRadius: Dp = PinkHouseDesignTokens.CardRadius,
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(cornerRadius))
            .background(
                Brush.verticalGradient(
                    listOf(Color(0xFFF7F2F4), Color(0xFFEFE8EC)),
                ),
            ),
        contentAlignment = Alignment.Center,
    ) {
        if (model != null) {
            AsyncImage(
                model = model,
                contentDescription = contentDescription,
                modifier = Modifier.fillMaxSize(),
                contentScale = contentScale,
            )
        } else if (placeholderIcon != null) {
            Icon(
                imageVector = placeholderIcon,
                contentDescription = null,
                tint = PinkHouseDesignTokens.Primary.copy(alpha = 0.45f),
                modifier = Modifier.size(36.dp),
            )
        }
    }
}

@Composable
fun PinkPillText(
    text: String,
    color: Color,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(999.dp),
        color = color.copy(alpha = 0.14f),
    ) {
        Text(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
            text = text,
            color = color,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

@Composable
fun HorizontalGap(width: Dp = 8.dp) {
    Spacer(Modifier.width(width))
}
