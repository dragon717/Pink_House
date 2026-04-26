package com.pinkhouse.android.core.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp

@Composable
fun FeaturePlaceholder(
    title: String,
    description: String,
    modifier: Modifier = Modifier,
    heroImageRes: Int? = null,
    backgroundImageRes: Int? = null,
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Color(0xFFF8E2E7)),
    ) {
        if (backgroundImageRes != null) {
            Image(
                painter = painterResource(backgroundImageRes),
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop,
                alpha = 0.32f,
            )
        }
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (heroImageRes != null) {
                Image(
                    painter = painterResource(heroImageRes),
                    contentDescription = title,
                    modifier = Modifier
                        .fillMaxWidth(0.62f)
                        .height(180.dp)
                        .clip(RoundedCornerShape(22.dp)),
                    contentScale = ContentScale.Fit,
                )
            }
            Surface(
                modifier = Modifier.padding(top = 16.dp),
                shape = RoundedCornerShape(22.dp),
                color = Color.White.copy(alpha = 0.86f),
            ) {
                Column(
                    modifier = Modifier
                        .background(
                            Brush.verticalGradient(
                                listOf(Color.White.copy(alpha = 0.92f), Color(0xFFFFF7FA).copy(alpha = 0.88f)),
                            ),
                        )
                        .padding(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(text = title, style = MaterialTheme.typography.headlineSmall)
                    Text(
                        text = description,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}
